import Foundation

// MARK: - Seeded random numbers

/// Deterministic random number generator (SplitMix64).
/// The same seed always gives the same sequence, so every experiment can be repeated exactly.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform number in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Standard normal sample (mean 0, standard deviation 1) using Box-Muller.
    mutating func nextNormal() -> Double {
        let u1 = max(nextUnit(), 1e-12)
        let u2 = nextUnit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

// MARK: - Price sensitivity

/// How strongly customers react to price changes (price elasticity of demand).
enum PriceSensitivity: String, CaseIterable, Identifiable, Codable {
    case low, medium, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var explanation: String {
        switch self {
        case .low: return "Few customers leave if the price goes up. Example: unique or custom items."
        case .medium: return "Some customers leave if the price goes up. Most student products."
        case .high: return "Many customers leave if the price goes up. Lots of similar options nearby."
        }
    }

    /// Elasticity: a 1% price increase loses about this many % of customers.
    var elasticity: Double {
        switch self {
        case .low: return 0.8
        case .medium: return 1.5
        case .high: return 2.5
        }
    }
}

// MARK: - Assumptions (the student's business model)

/// Which inputs a student can edit. Used to tag where each number came from.
enum Field: String, CaseIterable, Identifiable {
    case price, unitCost, fixedMonthlyCost, startingCash, demandLow, demandLikely, demandHigh, sensitivity
    var id: String { rawValue }
}

/// Where a number came from: the student, or an AI/starter guess (with a reason).
enum NumberSource: Equatable {
    case student
    case aiGuess(reason: String)        // filled in by the cloud AI
    case starterGuess(reason: String)   // filled in by the offline templates
}

struct Assumptions: Equatable, Codable {
    var price: Double = 20                 // what you charge per item
    var unitCost: Double = 8               // what each item costs you to make/buy
    var fixedMonthlyCost: Double = 300     // costs you pay every month even with zero sales
    var startingCash: Double = 500         // money you start with
    var demandLow: Double = 30             // customers per month: bad case
    var demandLikely: Double = 50          // customers per month: most likely
    var demandHigh: Double = 70            // customers per month: good case
    var sensitivity: PriceSensitivity = .medium
    var months: Int = 12

    /// The price the demand guesses were made at. Experiments change `price`
    /// but keep this, so demand reacts to the new price.
    var referencePrice: Double = 20

    // MARK: Demand

    /// Multiplier on customers when the price differs from the reference price.
    /// Constant-elasticity model: demand × (newPrice / oldPrice)^(-elasticity).
    func priceEffect(at p: Double) -> Double {
        guard referencePrice > 0, p > 0 else { return 1 }
        return pow(p / referencePrice, -sensitivity.elasticity)
    }

    var likelyCustomers: Double { demandLikely * priceEffect(at: price) }
    var lowCustomers: Double { demandLow * priceEffect(at: price) }

    // MARK: Lessons (simple formulas shown in Build)

    /// Margin: money kept from each sale.
    var margin: Double { price - unitCost }

    /// Break-even: sales per month needed to cover fixed costs. nil if each sale loses money.
    var breakEvenUnits: Double? {
        margin > 0 ? fixedMonthlyCost / margin : nil
    }

    /// Profit in a month at the likely number of customers.
    var likelyMonthlyProfit: Double { likelyCustomers * margin - fixedMonthlyCost }

    /// Profit in a month at the low number of customers.
    var lowMonthlyProfit: Double { lowCustomers * margin - fixedMonthlyCost }

    /// Months of cash if sales are slow (low case). nil means cash never runs out in the low case.
    var runwayMonthsIfSlow: Double? {
        let p = lowMonthlyProfit
        guard p < 0 else { return nil }
        return max(0, startingCash) / -p
    }

    /// After an experiment changes the price, rewrite the demand guesses at the new price
    /// so that `referencePrice == price` again. The model's behavior does not change.
    func rebased() -> Assumptions {
        var b = self
        let effect = priceEffect(at: price)
        b.demandLow = demandLow * effect
        b.demandLikely = demandLikely * effect
        b.demandHigh = demandHigh * effect
        b.referencePrice = price
        return b
    }

    // MARK: Validation

    var problems: [String] {
        var list: [String] = []
        if price <= 0 { list.append("Price must be more than $0.") }
        if unitCost < 0 { list.append("Cost per item can't be negative.") }
        if fixedMonthlyCost < 0 { list.append("Monthly costs can't be negative.") }
        if demandLow < 0 { list.append("Customers can't be negative.") }
        if !(demandLow <= demandLikely && demandLikely <= demandHigh) {
            list.append("Customers should go low ≤ likely ≤ high.")
        }
        return list
    }

    var isValid: Bool { problems.isEmpty }
}

// MARK: - Prediction (predict-first)

enum ProfitPrediction: String, CaseIterable, Identifiable {
    case profit = "Make money"
    case loss = "Lose money"
    case unsure = "Not sure"
    var id: String { rawValue }
}

struct Prediction: Equatable {
    var outcome: ProfitPrediction = .unsure
    var guessTotalProfit: Double? = nil
}

// MARK: - Stats and formatting

enum Stats {
    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// Nearest-rank percentile on an already sorted array.
    static func percentile(_ p: Double, of sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}

extension Double {
    var money: String {
        formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    var percent: String {
        formatted(.percent.precision(.fractionLength(0)))
    }

    var whole: String {
        formatted(.number.precision(.fractionLength(0)))
    }

    /// "3 in 10" style text for a probability.
    var outOfTen: String {
        "\(tenthsText) in 10"
    }

    /// Rounded to tenths, but never shows "0" when it happened at least once (shows "<1").
    var tenthsText: String {
        let n = Int((self * 10).rounded())
        return (n == 0 && self > 0) ? "<1" : "\(n)"
    }
}
