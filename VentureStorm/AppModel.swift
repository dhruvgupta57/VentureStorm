import SwiftUI
import Observation

enum Route: Hashable {
    case predict, results, fixIt
}

/// Holds the app's state and connects the screens to the engine and the AI.
@Observable
final class AppModel {
    // Build
    var buildStep = 0
    var idea = ""
    var assumptions = Assumptions()
    var sources: [Field: NumberSource] = [:]
    var draftSummary: String?
    var isDrafting = false

    // Predict + Results
    var prediction = Prediction()
    var seed: UInt64 = 42
    var report: AnalysisReport?
    var beforeFix: AnalysisReport?
    var appliedFixTitle: String?

    // Fix-It Coach
    var problem: Problem?
    var fixes: [TestedFix] = []
    var hintLevel = 0            // 0 = problem only, 1-2 = hints, 3 = show fixes
    var hints: [String] = []
    var fixNotes: [UUID: String] = [:]
    var usedAIWords = false

    var path: [Route] = []

    /// The saved business being worked on, if any. Saving again updates it.
    var currentBusinessID: UUID?

    /// Loads a saved business into Build so the student can rerun or change it.
    func open(_ business: SavedBusiness) {
        idea = business.idea
        assumptions = business.plan
        sources = [:]
        draftSummary = nil
        report = nil
        beforeFix = nil
        appliedFixTitle = nil
        resetCoach()
        currentBusinessID = business.id
        buildStep = 1
        path = []
    }

    /// Groq when a key is set (Secrets.swift or Settings), otherwise the offline templates.
    var ai: any VentureAI {
        if let key = KeychainStore.currentKey() { return GroqAI(apiKey: key) }
        return StarterAI()
    }

    /// Updated by Settings so screens can show whether AI is on.
    var aiConnected = KeychainStore.currentKey() != nil

    // MARK: Build

    /// Fills the Build cards from the typed idea. Numbers are tagged until the student edits them.
    func fillFromIdea() async {
        let text = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isDrafting = true
        defer { isDrafting = false }

        let draft: IdeaDraft
        do {
            draft = try await ai.draft(idea: text)
        } catch {
            // Cloud AI failed or isn't connected: fall back to the offline starter.
            guard let fallback = try? await StarterAI().draft(idea: text) else { return }
            draft = fallback
        }

        assumptions = draft.assumptions
        sources = [:]
        for field in Field.allCases {
            let reason = draft.reasons[field] ?? "Starting estimate."
            sources[field] = draft.isOffline ? .starterGuess(reason: reason) : .aiGuess(reason: reason)
        }
        draftSummary = draft.summary
    }

    /// Called whenever the student edits a field: it now counts as their own number.
    func markStudent(_ field: Field) {
        sources[field] = .student
    }

    // MARK: Run

    func run() {
        report = Detective.analyze(assumptions, seed: seed)
        resetCoach()
    }

    func startFresh() {
        beforeFix = nil
        appliedFixTitle = nil
        run()
    }

    func tryNewFutures() {
        seed &+= 1
        beforeFix = nil
        appliedFixTitle = nil
        run()
    }

    // MARK: Fix-It Coach

    func resetCoach() {
        problem = nil
        fixes = []
        hintLevel = 0
        hints = []
        fixNotes = [:]
        usedAIWords = false
    }

    /// Engine finds the problem and tests fixes; AI (if connected) only rewrites the words.
    func prepareCoach() async {
        guard let report else { return }
        let found = FixItCoach.diagnose(report)
        let actions = FixItCoach.candidates(for: found, report: report)
        let tested = FixItCoach.testFixes(for: found, report: report, actions: actions)

        problem = found
        fixes = tested
        hints = found.hints
        fixNotes = [:]
        usedAIWords = false

        guard let words = try? await ai.coach(problem: found, fixes: tested, report: report) else { return }

        // Number guard: only keep AI text whose numbers all come from the engine.
        let allowed = NumberGuard.allowedNumbers(report: report, fixes: tested)
        if words.hints.count == found.hints.count,
           words.hints.allSatisfy({ NumberGuard.isSafe($0, allowed: allowed) }),
           words.hints != found.hints {
            hints = words.hints
            usedAIWords = true
        }
        for (id, note) in words.fixNotes where NumberGuard.isSafe(note, allowed: allowed) {
            fixNotes[id] = note
            usedAIWords = true
        }
    }

    func apply(_ fix: TestedFix) {
        beforeFix = report
        appliedFixTitle = fix.title
        assumptions = fix.newAssumptions
        for field in fieldsChanged(by: fix.action) { sources[field] = .student }
        report = Detective.analyze(assumptions, seed: seed)
        resetCoach()
        path = [.results]
    }

    private func fieldsChanged(by action: FixAction) -> [Field] {
        switch action {
        case .price: return [.price, .demandLow, .demandLikely, .demandHigh]
        case .unitCost: return [.unitCost]
        case .fixedCost: return [.fixedMonthlyCost]
        case .startingCash: return [.startingCash]
        }
    }
}
