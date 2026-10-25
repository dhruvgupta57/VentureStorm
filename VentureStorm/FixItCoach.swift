import Foundation

// MARK: - Problems the engine can spot (rule-based, no AI)

enum ProblemKind {
    case losesMoneyPerSale
    case breakEvenOutOfReach
    case runsOutOfCash
    case oftenLosesMoney
    case fixedCostsTooHeavy
    case healthy

    /// Cash problems are judged by "chance of running out"; the rest by profit.
    var isCashProblem: Bool { self == .runsOutOfCash }
}

struct Problem {
    let kind: ProblemKind
    let title: String
    let detail: String
    /// Two hints, from small nudge to bigger nudge. Level 3 = show the fixes.
    let hints: [String]
}

// MARK: - Fixes the coach can try

enum FixAction: Equatable {
    case price(Double)
    case unitCost(Double)
    case fixedCost(Double)
    case startingCash(Double)

    /// Groups fixes so the coach shows variety (best price fix, best cost fix, ...).
    var group: String {
        switch self {
        case .price: return "price"
        case .unitCost: return "unitCost"
        case .fixedCost: return "fixedCost"
        case .startingCash: return "startingCash"
        }
    }

    /// Applies the fix. A price change keeps the old reference price, so customers react to it.
    func apply(to a: Assumptions) -> Assumptions {
        var b = a
        switch self {
        case .price(let p): b.price = p
        case .unitCost(let c): b.unitCost = c
        case .fixedCost(let f): b.fixedMonthlyCost = f
        case .startingCash(let s): b.startingCash = s
        }
        return b
    }

    func title(from a: Assumptions) -> String {
        switch self {
        case .price(let p):
            return p > a.price ? "Raise price to \(p.money)" : "Lower price to \(p.money)"
        case .unitCost(let c):
            return "Cut cost per item to \(c.money)"
        case .fixedCost(let f):
            return "Cut monthly costs to \(f.money)"
        case .startingCash(let s):
            return "Start with \(s.money) in cash"
        }
    }

    /// What the student would actually do in real life.
    var howToDoIt: String {
        switch self {
        case .price: return "Test the new price with a few customers first."
        case .unitCost: return "Find a cheaper supplier, buy in bulk, or simplify the design."
        case .fixedCost: return "Drop or swap your most expensive monthly cost."
        case .startingCash: return "Save up more before launching, or start smaller."
        }
    }
}

/// A fix that the engine has actually simulated, with before and after numbers.
struct TestedFix: Identifiable {
    let id = UUID()
    let action: FixAction
    let title: String
    let howToDoIt: String
    let tradeoff: String
    let before: SimSummary
    let after: SimSummary
    let newAssumptions: Assumptions
}

// MARK: - Coach

enum FixItCoach {

    /// Spots the most serious problem. Order matters: the first match wins.
    static func diagnose(_ r: AnalysisReport) -> Problem {
        let a = r.assumptions
        let s = r.summary
        let weakest = r.weakestGuess?.driver.name ?? "your guesses"

        if a.margin <= 0 {
            return Problem(
                kind: .losesMoneyPerSale,
                title: "You lose money on every sale",
                detail: "Each item costs you \(a.unitCost.money) but sells for \(a.price.money). Selling more makes it worse.",
                hints: [
                    "Check your margin.",
                    "Each sale brings in \(a.price.money) and costs \(a.unitCost.money). Which number can you change?"
                ])
        }

        if let be = a.breakEvenUnits, be > a.likelyCustomers {
            return Problem(
                kind: .breakEvenOutOfReach,
                title: "Break-even is out of reach",
                detail: "You need about \(be.rounded(.up).whole) sales a month to cover your costs, but you expect about \(a.likelyCustomers.whole).",
                hints: [
                    "Compare how many sales you need with how many you expect.",
                    "You need \(be.rounded(.up).whole) sales but expect \(a.likelyCustomers.whole). A higher margin or lower monthly costs lowers the number you need."
                ])
        }

        if s.chanceOutOfCash >= 0.2 {
            let months = s.outcomes.compactMap(\.monthRanOut).map { Double($0) }.sorted()
            let typicalMonth = Stats.percentile(0.5, of: months)
            return Problem(
                kind: .runsOutOfCash,
                title: "You could run out of cash",
                detail: "In \(s.chanceOutOfCash.outOfTen) futures your cash drops below $0, usually around month \(typicalMonth.whole).",
                hints: [
                    "Check your cash in the first few months.",
                    "In \(s.chanceOutOfCash.outOfTen) futures cash runs out around month \(typicalMonth.whole). What would add cash early?"
                ])
        }

        if s.chanceOfLoss >= 0.3 {
            return Problem(
                kind: .oftenLosesMoney,
                title: "You often lose money",
                detail: "You lose money in \(s.chanceOfLoss.outOfTen) futures.",
                hints: [
                    "Check the bad futures, not just the average.",
                    "You lose money in \(s.chanceOfLoss.outOfTen) futures. \(weakest) has the biggest effect."
                ])
        }

        let grossPerMonth = a.likelyCustomers * a.margin
        if grossPerMonth > 0, a.fixedMonthlyCost / grossPerMonth >= 0.6 {
            let share = a.fixedMonthlyCost / grossPerMonth
            return Problem(
                kind: .fixedCostsTooHeavy,
                title: "Monthly costs are too high",
                detail: "Monthly costs use \(share.percent) of what you keep from sales.",
                hints: [
                    "Which costs do you pay even with no sales?",
                    "Monthly costs use \(share.percent) of your earnings. Lower them or raise your margin."
                ])
        }

        return Problem(
            kind: .healthy,
            title: "No major problems",
            detail: "You make money in \((1 - s.chanceOfLoss).outOfTen) futures. Next, test your inputs in real life.",
            hints: [
                "Which input is easiest to change?",
                "\(weakest) has the biggest effect. Test it before spending money."
            ])
    }

    /// Candidate fixes to try. The engine decides which ones actually help.
    static func candidates(for problem: Problem, report r: AnalysisReport) -> [FixAction] {
        let a = r.assumptions
        var list: [FixAction] = []

        // Price: try up and down. Customers react, so higher is not automatically better.
        var prices = [0.9, 1.1, 1.2, 1.3].map { tidy(a.price * $0) }
        if a.margin <= 0 { prices += [tidy(a.unitCost * 1.3), tidy(a.unitCost * 1.5)] }
        list += prices.filter { $0 > 0 && $0 != a.price }.map { FixAction.price($0) }

        // Cost per item and monthly costs.
        if a.unitCost > 0 { list += [0.85, 0.7].map { FixAction.unitCost(tidy(a.unitCost * $0)) } }
        if a.fixedMonthlyCost > 0 { list += [0.75, 0.5].map { FixAction.fixedCost(tidy(a.fixedMonthlyCost * $0)) } }

        // More starting cash: enough to survive a bad (10th percentile) future.
        let shortfall = -r.summary.badCaseLowestCash
        if shortfall > 0 {
            let extra = (shortfall / 50).rounded(.up) * 50
            list.append(.startingCash(a.startingCash + extra))
        }
        return list
    }

    /// Runs each candidate on the SAME futures as the original, keeps only the ones that help,
    /// and returns the best one from each group (up to 3).
    static func testFixes(for problem: Problem, report r: AnalysisReport, actions: [FixAction]) -> [TestedFix] {
        let a = r.assumptions
        let draws = Detective.draws(for: a, seed: r.seed)
        let before = r.summary

        var bestPerGroup: [String: (score: Double, fix: TestedFix)] = [:]

        for action in actions {
            let newA = action.apply(to: a)
            guard newA.isValid else { continue }
            let after = Simulator.run(newA, draws: draws)
            guard let score = score(problem.kind, before: before, after: after) else { continue }

            let fix = TestedFix(
                action: action,
                title: action.title(from: a),
                howToDoIt: action.howToDoIt,
                tradeoff: tradeoff(action, base: a),
                before: before,
                after: after,
                newAssumptions: newA.rebased()
            )
            if let current = bestPerGroup[action.group], current.score >= score { continue }
            bestPerGroup[action.group] = (score, fix)
        }

        return bestPerGroup.values
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map { $0.fix }
    }

    /// How much a fix helps the specific problem. nil = it doesn't help, so it's hidden.
    static func score(_ kind: ProblemKind, before: SimSummary, after: SimSummary) -> Double? {
        if kind.isCashProblem {
            let gain = before.chanceOutOfCash - after.chanceOutOfCash
            return gain > 0.001 ? gain * 10_000 + (after.meanProfit - before.meanProfit) * 0.001 : nil
        } else {
            let gain = after.meanProfit - before.meanProfit
            let riskOK = after.chanceOfLoss <= before.chanceOfLoss + 0.001
            return (gain > 1 && riskOK) ? gain : nil
        }
    }

    static func tradeoff(_ action: FixAction, base a: Assumptions) -> String {
        switch action {
        case .price(let p):
            let newCustomers = a.demandLikely * a.priceEffect(at: p)
            return "You'd get about \(newCustomers.whole) customers a month instead of \(a.likelyCustomers.whole)."
        case .unitCost:
            return "Cheaper supplies can mean lower quality. Check a sample first."
        case .fixedCost:
            return "Requires cutting or replacing a monthly cost."
        case .startingCash(let s):
            return "You'd need \((s - a.startingCash).money) more before you start."
        }
    }

    /// Rounds to a friendly number: whole dollars for $5+, otherwise to the quarter.
    static func tidy(_ x: Double) -> Double {
        x >= 5 ? x.rounded() : (x * 4).rounded() / 4
    }
}
