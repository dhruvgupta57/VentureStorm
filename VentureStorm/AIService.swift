import Foundation

// MARK: - What the AI is allowed to produce

/// Starting numbers drafted from a typed idea. The student must confirm or edit every one.
struct IdeaDraft {
    var assumptions: Assumptions
    var reasons: [Field: String]
    var summary: String
    /// true = made by the built-in starter templates, not the cloud AI.
    var isOffline: Bool
}

/// Words the AI writes for the Fix-It Coach. It never produces numbers of its own:
/// every number in this text must already exist in the engine's report (see NumberGuard).
struct CoachWords {
    var hints: [String]
    var fixNotes: [UUID: String]
}

/// The AI's three jobs. The engine does all of the math.
protocol VentureAI {
    func draft(idea: String) async throws -> IdeaDraft
    func coach(problem: Problem, fixes: [TestedFix], report: AnalysisReport) async throws -> CoachWords
}

enum AIError: Error {
    case notConnected
    case badResponse
}

// The cloud AI is GroqAI (GroqAI.swift). It is used when a key is saved in Settings.

// MARK: - Offline starter (no AI, works with no internet)

/// Simple keyword templates so "Describe your idea" works offline.
struct StarterAI: VentureAI {

    private struct Template {
        let keywords: [String]
        let name: String
        let price: Double, unitCost: Double, fixed: Double, cash: Double
        let low: Double, likely: Double, high: Double
        let sensitivity: PriceSensitivity
        let costReason: String, fixedReason: String, demandReason: String
    }

    private let templates: [Template] = [
        Template(keywords: ["hoodie", "shirt", "tee", "merch", "sticker", "apparel", "clothing"],
                 name: "custom merch", price: 25, unitCost: 12, fixed: 40, cash: 300,
                 low: 10, likely: 25, high: 45, sensitivity: .medium,
                 costReason: "Blank item plus printing usually costs about half the price.",
                 fixedReason: "Design app plus a small online store fee.",
                 demandReason: "A new student brand often sells a few dozen a month at first."),
        Template(keywords: ["bake", "cookie", "cupcake", "brownie", "food", "snack", "lemonade", "candy"],
                 name: "baked goods", price: 3, unitCost: 1, fixed: 25, cash: 100,
                 low: 40, likely: 80, high: 150, sensitivity: .high,
                 costReason: "Ingredients and packaging per item.",
                 fixedReason: "Containers, labels and a table fee.",
                 demandReason: "Cheap snacks sell in higher numbers, but buyers compare prices."),
        Template(keywords: ["tutor", "lesson", "coach", "teach", "class"],
                 name: "tutoring", price: 25, unitCost: 2, fixed: 15, cash: 50,
                 low: 4, likely: 10, high: 20, sensitivity: .medium,
                 costReason: "Each hour has small costs like printing or travel.",
                 fixedReason: "Scheduling app or ads.",
                 demandReason: "Counting each hour of tutoring as one sale."),
        Template(keywords: ["resell", "sneaker", "thrift", "flip", "vintage", "card"],
                 name: "reselling", price: 60, unitCost: 40, fixed: 30, cash: 400,
                 low: 3, likely: 8, high: 15, sensitivity: .high,
                 costReason: "What you pay for each item, plus shipping.",
                 fixedReason: "Selling-app fees and supplies.",
                 demandReason: "Resellers usually move a handful of items a month at first."),
    ]

    func draft(idea: String) async throws -> IdeaDraft {
        let text = idea.lowercased()
        let t = templates.first { $0.keywords.contains { text.contains($0) } }

        var a = Assumptions()
        var reasons: [Field: String] = [:]
        let label: String

        if let t {
            a.price = t.price; a.unitCost = t.unitCost; a.fixedMonthlyCost = t.fixed; a.startingCash = t.cash
            a.demandLow = t.low; a.demandLikely = t.likely; a.demandHigh = t.high
            a.sensitivity = t.sensitivity
            reasons[.price] = "Typical starting price for \(t.name)."
            reasons[.unitCost] = t.costReason
            reasons[.fixedMonthlyCost] = t.fixedReason
            reasons[.startingCash] = "Enough to buy a first batch."
            reasons[.demandLikely] = t.demandReason
            reasons[.demandLow] = "A slow month."
            reasons[.demandHigh] = "A great month."
            reasons[.sensitivity] = t.sensitivity.explanation
            label = t.name
        } else {
            reasons[.price] = "General starting guess. Change it to your real price."
            reasons[.demandLikely] = "General starting guess. Change it to your real estimate."
            label = "a small product business"
        }

        // If the student typed a price like "$25", use it.
        if let typed = Self.firstDollarAmount(in: idea) {
            a.price = typed
            reasons[.price] = "You said \(typed.money)."
        }
        a.referencePrice = a.price

        return IdeaDraft(
            assumptions: a,
            reasons: reasons,
            summary: "Starting numbers for \(label). Edit any that don't match your plan.",
            isOffline: true
        )
    }

    func coach(problem: Problem, fixes: [TestedFix], report: AnalysisReport) async throws -> CoachWords {
        CoachWords(hints: problem.hints, fixNotes: [:])
    }

    /// Finds the first "$25" or "25 dollars" style amount.
    static func firstDollarAmount(in text: String) -> Double? {
        let pattern = #"\$\s?(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s?(?:dollars|bucks)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        for i in 1...2 {
            if let r = Range(match.range(at: i), in: text), let v = Double(text[r]), v > 0 { return v }
        }
        return nil
    }
}

// MARK: - Number guard

/// Checks that AI text only uses numbers the engine already calculated.
/// If any number doesn't match, the app throws the text away and shows the template text instead.
enum NumberGuard {
    static func allowedNumbers(report r: AnalysisReport, fixes: [TestedFix]) -> [Double] {
        let a = r.assumptions
        let s = r.summary
        var list: [Double] = [
            a.price, a.unitCost, a.fixedMonthlyCost, a.startingCash,
            a.demandLow, a.demandLikely, a.demandHigh, a.likelyCustomers, a.margin,
            a.likelyMonthlyProfit, Double(a.months),
            s.meanProfit, s.median, s.p10, s.p90,
            s.chanceOfLoss * 100, s.chanceOutOfCash * 100,
            (s.chanceOfLoss * 10).rounded(), (s.chanceOutOfCash * 10).rounded(),
        ]
        if let be = a.breakEvenUnits { list += [be, be.rounded(.up)] }
        for x in r.sensitivities { list += [x.lowMeanProfit, x.highMeanProfit, x.swing] }
        for f in fixes {
            list += [f.after.meanProfit, f.after.chanceOfLoss * 100, f.after.chanceOutOfCash * 100,
                     (f.after.chanceOfLoss * 10).rounded(), (f.after.chanceOutOfCash * 10).rounded(),
                     f.newAssumptions.price, f.newAssumptions.unitCost,
                     f.newAssumptions.fixedMonthlyCost, f.newAssumptions.startingCash]
        }
        list += (0...12).map { Double($0) }   // small counts like "3 in 10" or "month 4"
        return list
    }

    /// true if every number in `text` is within 1% (or $1) of an allowed number.
    static func isSafe(_ text: String, allowed: [Double]) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\d[\d,]*(?:\.\d+)?"#) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text),
                  let value = Double(text[r].replacingOccurrences(of: ",", with: "")) else { return false }
            let ok = allowed.contains { abs(abs($0) - value) <= max(1, abs($0) * 0.01) }
            if !ok { return false }
        }
        return true
    }
}
