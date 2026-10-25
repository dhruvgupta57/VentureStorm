import Foundation

/// Cloud AI using Groq's free API (OpenAI-compatible chat completions).
/// It only writes words and starting guesses. The engine still does all the math,
/// and AppModel checks every number in the hints with NumberGuard.
struct GroqAI: VentureAI {
    let apiKey: String
    var model = "openai/gpt-oss-20b"

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    // MARK: Idea -> starting numbers

    func draft(idea: String) async throws -> IdeaDraft {
        let system = """
        You estimate starting numbers for a high school student's small business.
        Reply with JSON only, using exactly these keys:
        "summary": one short sentence,
        "price", "unitCost", "fixedMonthlyCost", "startingCash": numbers in US dollars,
        "demandLow", "demandLikely", "demandHigh": customers per month at that price (slow, normal, great month),
        "sensitivity": "low", "medium" or "high" (how many customers leave if the price goes up),
        "reasons": an object with the keys price, unitCost, fixedMonthlyCost, startingCash, demandLow, demandLikely, demandHigh, sensitivity, each a plain sentence under 12 words.
        Use realistic, modest numbers for a student business. If the student gives a number, use it.
        """
        let data = try await chat(system: system, user: "Business idea: \(idea)")
        let reply = try JSONDecoder().decode(DraftReply.self, from: data)

        var a = Assumptions()
        a.price = reply.price.value
        a.unitCost = reply.unitCost.value
        a.fixedMonthlyCost = reply.fixedMonthlyCost.value
        a.startingCash = reply.startingCash.value
        // Keep the three demand guesses in order, whatever order the AI sent them in.
        let demand = [reply.demandLow.value, reply.demandLikely.value, reply.demandHigh.value].sorted()
        a.demandLow = demand[0]
        a.demandLikely = demand[1]
        a.demandHigh = demand[2]
        a.sensitivity = PriceSensitivity(rawValue: reply.sensitivity?.lowercased() ?? "") ?? .medium
        a.referencePrice = a.price

        // Reject answers that don't make sense; the app then uses the starter templates.
        guard a.isValid, a.price <= 200, a.unitCost <= 200, a.fixedMonthlyCost <= 2000,
              a.startingCash <= 5000, a.demandHigh <= 500 else {
            throw AIError.badResponse
        }

        var reasons: [Field: String] = [:]
        for field in Field.allCases {
            if let text = reply.reasons?[field.rawValue], !text.isEmpty { reasons[field] = text }
        }

        return IdeaDraft(
            assumptions: a,
            reasons: reasons,
            summary: reply.summary ?? "Starting numbers from AI. Edit any that don't match your plan.",
            isOffline: false
        )
    }

    // MARK: Fix-It wording

    func coach(problem: Problem, fixes: [TestedFix], report: AnalysisReport) async throws -> CoachWords {
        let a = report.assumptions
        var lines: [String] = [
            "Business: price \(a.price.money), cost per item \(a.unitCost.money), monthly costs \(a.fixedMonthlyCost.money), starting cash \(a.startingCash.money), about \(a.likelyCustomers.whole) customers a month.",
            "Problem: \(problem.title). \(problem.detail)",
            "Hint 1: \(problem.hints.first ?? "")",
            "Hint 2: \(problem.hints.last ?? "")",
        ]
        for (i, fix) in fixes.enumerated() {
            lines.append("Fix \(i + 1): \(fix.title). Average profit \(fix.before.meanProfit.money) -> \(fix.after.meanProfit.money). Trade-off: \(fix.tradeoff)")
        }

        let system = """
        You coach high school students on their small business. Use short, plain sentences.
        Rewrite the two hints for this student's situation. Hint 1 is a small nudge, hint 2 is a bigger nudge. Do not give the answer away in the hints.
        Then write one note per fix saying how to do it in real life (under 20 words each).
        Only use numbers that appear in the input. Do not invent any new numbers.
        Reply with JSON only: {"hints": [string, string], "fixNotes": [string, ...]} with one fixNote per fix, in order.
        """
        let data = try await chat(system: system, user: lines.joined(separator: "\n"))
        let reply = try JSONDecoder().decode(CoachReply.self, from: data)

        var notes: [UUID: String] = [:]
        for (fix, note) in zip(fixes, reply.fixNotes ?? []) where !note.isEmpty {
            notes[fix.id] = note
        }
        return CoachWords(hints: reply.hints ?? [], fixNotes: notes)
    }

    // MARK: Request

    /// Sends one chat request and returns the JSON text the model wrote.
    private func chat(system: String, user: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.badResponse
        }
        let reply = try JSONDecoder().decode(ChatReply.self, from: data)
        guard let text = reply.choices.first?.message.content,
              let json = text.data(using: .utf8) else {
            throw AIError.badResponse
        }
        return json
    }

    /// Quick check used by Settings: true if the key works.
    func test() async -> Bool {
        (try? await chat(system: "Reply with JSON only: {\"ok\": true}", user: "ping")) != nil
    }
}

// MARK: - Response shapes

private struct ChatReply: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct DraftReply: Decodable {
    let summary: String?
    let price, unitCost, fixedMonthlyCost, startingCash: FlexibleNumber
    let demandLow, demandLikely, demandHigh: FlexibleNumber
    let sensitivity: String?
    let reasons: [String: String]?
}

private struct CoachReply: Decodable {
    let hints: [String]?
    let fixNotes: [String]?
}

/// Accepts 25, 25.5 or "25" / "$25" from the model.
private struct FlexibleNumber: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self),
                  let d = Double(s.filter { "0123456789.".contains($0) }) {
            value = d
        } else {
            throw AIError.badResponse
        }
    }
}
