import Foundation

/// The random "luck" for one possible future. Generated once from the seed and reused
/// for every experiment, so differences between runs come from the assumptions, not luck.
struct FutureDraw {
    /// Where this future lands between the low and high customer guesses (0...1).
    let marketLevel: Double
    /// Month-to-month wobble (standard normal values).
    let monthlyNoise: [Double]
}

/// The result of one simulated future.
struct ScenarioOutcome: Identifiable {
    let id: Int
    let totalProfit: Double
    let endingCash: Double
    let lowestCash: Double
    /// First month (1-based) where cash went below $0, or nil if it never did.
    let monthRanOut: Int?
    /// Cash at the start and after each month (months + 1 values). Used by the futures chart.
    let cashPath: [Double]

    var ranOutOfCash: Bool { monthRanOut != nil }
}

/// Summary numbers for one simulation run.
struct SimSummary {
    let outcomes: [ScenarioOutcome]

    var sortedProfits: [Double] { outcomes.map(\.totalProfit).sorted() }
    var meanProfit: Double { Stats.mean(outcomes.map(\.totalProfit)) }
    var p10: Double { Stats.percentile(0.10, of: sortedProfits) }
    var median: Double { Stats.percentile(0.50, of: sortedProfits) }
    var p90: Double { Stats.percentile(0.90, of: sortedProfits) }

    var chanceOfLoss: Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.filter { $0.totalProfit < 0 }.count) / Double(outcomes.count)
    }

    var chanceOutOfCash: Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.filter(\.ranOutOfCash).count) / Double(outcomes.count)
    }

    /// Lowest cash point in a bad (10th percentile) future. Used to size a "start with more cash" fix.
    var badCaseLowestCash: Double {
        Stats.percentile(0.10, of: outcomes.map(\.lowestCash).sorted())
    }

    /// The future whose total profit is closest to the median. Drawn as the bold "typical" line.
    var typicalOutcome: ScenarioOutcome? {
        let m = median
        return outcomes.min { abs($0.totalProfit - m) < abs($1.totalProfit - m) }
    }
}

enum Simulator {
    static let monthlyNoiseSize = 0.10   // ±10% month-to-month wobble (1 standard deviation)

    /// Makes the random draws once from a seed.
    static func makeDraws(futures: Int, months: Int, seed: UInt64) -> [FutureDraw] {
        var rng = SeededRNG(seed: seed)
        return (0..<futures).map { _ in
            FutureDraw(
                marketLevel: rng.nextUnit(),
                monthlyNoise: (0..<months).map { _ in rng.nextNormal() }
            )
        }
    }

    /// Turns a 0...1 market level into customers per month using a triangular
    /// distribution between the student's low, likely and high guesses.
    static func baseCustomers(level u: Double, low: Double, likely: Double, high: Double) -> Double {
        guard high > low else { return likely }
        let split = (likely - low) / (high - low)
        if u < split {
            return low + sqrt(u * (high - low) * (likely - low))
        } else {
            return high - sqrt((1 - u) * (high - low) * (high - likely))
        }
    }

    /// Runs every future with the given assumptions. Pure arithmetic: no AI involved.
    static func run(_ a: Assumptions, draws: [FutureDraw]) -> SimSummary {
        let effect = a.priceEffect(at: a.price)

        let outcomes = draws.enumerated().map { index, draw -> ScenarioOutcome in
            let base = baseCustomers(level: draw.marketLevel,
                                     low: a.demandLow, likely: a.demandLikely, high: a.demandHigh)
            var cash = a.startingCash
            var total = 0.0
            var lowest = cash
            var ranOut: Int? = nil
            var path: [Double] = [cash]

            for (m, z) in draw.monthlyNoise.prefix(a.months).enumerated() {
                let customers = max(0, (base * effect * (1 + monthlyNoiseSize * z)).rounded())
                let profit = customers * (a.price - a.unitCost) - a.fixedMonthlyCost
                total += profit
                cash += profit
                lowest = min(lowest, cash)
                path.append(cash)
                if cash < 0 && ranOut == nil { ranOut = m + 1 }
            }

            return ScenarioOutcome(id: index, totalProfit: total, endingCash: cash,
                                   lowestCash: lowest, monthRanOut: ranOut, cashPath: path)
        }
        return SimSummary(outcomes: outcomes)
    }
}
