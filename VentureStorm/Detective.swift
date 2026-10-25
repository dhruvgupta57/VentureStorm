import Foundation

/// The guesses Assumption Detective tests, one at a time.
enum Driver: String, CaseIterable, Identifiable {
    case demand, price, unitCost, fixedCost

    var id: String { rawValue }

    var name: String {
        switch self {
        case .demand: return "Customers"
        case .price: return "Price"
        case .unitCost: return "Cost per item"
        case .fixedCost: return "Monthly costs"
        }
    }

    /// What range is tested. Shown on screen so the test is transparent.
    var rangeText: String {
        switch self {
        case .demand: return "your low vs. high guess"
        case .price: return "±10% (customers react)"
        case .unitCost: return "±10%"
        case .fixedCost: return "±10%"
        }
    }

    /// Returns the "low" and "high" versions of the assumptions for this test.
    func testCases(_ a: Assumptions) -> (low: Assumptions, high: Assumptions) {
        var low = a, high = a
        switch self {
        case .demand:
            low.demandLow = a.demandLow; low.demandLikely = a.demandLow; low.demandHigh = a.demandLow
            high.demandLow = a.demandHigh; high.demandLikely = a.demandHigh; high.demandHigh = a.demandHigh
        case .price:
            low.price = a.price * 0.9
            high.price = a.price * 1.1
        case .unitCost:
            low.unitCost = a.unitCost * 0.9
            high.unitCost = a.unitCost * 1.1
        case .fixedCost:
            low.fixedMonthlyCost = a.fixedMonthlyCost * 0.9
            high.fixedMonthlyCost = a.fixedMonthlyCost * 1.1
        }
        return (low, high)
    }

    /// A cheap real-world test a student can run this week to check this guess.
    var realWorldTest: String {
        switch self {
        case .demand: return "Pre-sell to 15 people this week or run a poll. Count only firm yeses."
        case .price: return "Ask 10 people if they'd pay your price, and 10 others if they'd pay 20% more."
        case .unitCost: return "Get quotes from 2 more suppliers and compare cost per item."
        case .fixedCost: return "List every monthly cost and look for a cheaper or free option for the biggest one."
        }
    }
}

struct SensitivityResult: Identifiable {
    let driver: Driver
    let lowMeanProfit: Double
    let highMeanProfit: Double
    let lowChanceOfLoss: Double
    let highChanceOfLoss: Double

    var id: String { driver.id }
    /// How much average total profit moves across the tested range.
    var swing: Double { abs(highMeanProfit - lowMeanProfit) }
}

/// Everything the Results screen shows for one run.
struct AnalysisReport {
    let assumptions: Assumptions
    let seed: UInt64
    let summary: SimSummary
    let sensitivities: [SensitivityResult]   // sorted, biggest swing first

    var weakestGuess: SensitivityResult? { sensitivities.first }
}

enum Detective {
    static let futures = 500

    static func draws(for a: Assumptions, seed: UInt64) -> [FutureDraw] {
        Simulator.makeDraws(futures: futures, months: a.months, seed: seed)
    }

    static func analyze(_ a: Assumptions, seed: UInt64) -> AnalysisReport {
        let draws = draws(for: a, seed: seed)
        let summary = Simulator.run(a, draws: draws)
        let sensitivities = Driver.allCases
            .map { sensitivity(for: $0, base: a, draws: draws) }
            .sorted { $0.swing > $1.swing }
        return AnalysisReport(assumptions: a, seed: seed, summary: summary, sensitivities: sensitivities)
    }

    /// Paired test: the low and high runs use the same random futures,
    /// so any difference comes only from the guess being tested.
    static func sensitivity(for driver: Driver, base: Assumptions, draws: [FutureDraw]) -> SensitivityResult {
        let cases = driver.testCases(base)
        let low = Simulator.run(cases.low, draws: draws)
        let high = Simulator.run(cases.high, draws: draws)
        return SensitivityResult(
            driver: driver,
            lowMeanProfit: low.meanProfit,
            highMeanProfit: high.meanProfit,
            lowChanceOfLoss: low.chanceOfLoss,
            highChanceOfLoss: high.chanceOfLoss
        )
    }

    /// Summary of the biggest driver. Every number comes from the report.
    static func weakestGuessText(_ r: AnalysisReport) -> String {
        guard let top = r.weakestGuess else { return "" }
        let worse = min(top.lowMeanProfit, top.highMeanProfit)
        let better = max(top.lowMeanProfit, top.highMeanProfit)
        return "\(top.driver.name) has the biggest effect. Across \(top.driver.rangeText), average profit goes from \(worse.money) to \(better.money)."
    }
}
