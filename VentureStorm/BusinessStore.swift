import Foundation
import Observation

// MARK: - Saved data

/// One week of real results that the student logs.
struct SalesLog: Identifiable, Codable, Equatable {
    var id = UUID()
    var weekOf: Date
    var unitsSold: Double
    var pricePerUnit: Double
    var moneySpent: Double

    var revenue: Double { unitsSold * pricePerUnit }
    var profit: Double { revenue - moneySpent }
}

/// A business plan the student saved, plus its real sales.
struct SavedBusiness: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var idea: String
    var plan: Assumptions
    var createdAt = Date()
    var updatedAt = Date()
    var logs: [SalesLog] = []

    var sortedLogs: [SalesLog] { logs.sorted { $0.weekOf < $1.weekOf } }
}

// MARK: - Real results vs. the plan

struct TrackerSummary {
    static let weeksPerMonth = 52.0 / 12.0

    let weeks: Int
    let totalRevenue: Double
    let totalSpent: Double
    let totalProfit: Double
    /// Customers per month at the real sales pace.
    let monthlyPace: Double
    /// The "normal month" guess from the plan.
    let guessedMonthly: Double

    init(_ b: SavedBusiness) {
        weeks = b.logs.count
        totalRevenue = b.logs.reduce(0) { $0 + $1.revenue }
        totalSpent = b.logs.reduce(0) { $0 + $1.moneySpent }
        totalProfit = totalRevenue - totalSpent
        let units = b.logs.reduce(0) { $0 + $1.unitsSold }
        monthlyPace = weeks > 0 ? units / Double(weeks) * Self.weeksPerMonth : 0
        guessedMonthly = b.plan.demandLikely
    }

    /// 1.0 = exactly on your guess, 0.6 = 60% of your guess.
    var paceVsGuess: Double { guessedMonthly > 0 ? monthlyPace / guessedMonthly : 0 }
}

struct ProfitPoint: Identifiable {
    let id: UUID
    let date: Date
    let total: Double
}

struct Milestone: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let achieved: Bool
}

enum Tracker {
    /// Running total of profit, week by week.
    static func cumulativeProfit(_ b: SavedBusiness) -> [ProfitPoint] {
        var total = 0.0
        return b.sortedLogs.map { log in
            total += log.profit
            return ProfitPoint(id: log.id, date: log.weekOf, total: total)
        }
    }

    /// The plan with the customer guesses moved to the real sales pace,
    /// keeping the same spread between slow and great months.
    static func realityPlan(_ b: SavedBusiness) -> Assumptions? {
        let s = TrackerSummary(b)
        guard s.weeks > 0, b.plan.demandLikely > 0 else { return nil }
        let ratio = s.paceVsGuess
        var a = b.plan
        a.demandLow *= ratio
        a.demandLikely *= ratio
        a.demandHigh *= ratio
        return a.isValid ? a : nil
    }

    static func milestones(_ b: SavedBusiness) -> [Milestone] {
        let s = TrackerSummary(b)
        let logs = b.logs
        return [
            Milestone(id: "first-log", title: "First week logged",
                      detail: "Start tracking real sales.", icon: "list.bullet.clipboard",
                      achieved: !logs.isEmpty),
            Milestone(id: "first-sale", title: "First sale",
                      detail: "Sell at least one item.", icon: "cart.fill",
                      achieved: logs.contains { $0.unitsSold > 0 }),
            Milestone(id: "profit-week", title: "Profitable week",
                      detail: "Make more than you spend in a week.", icon: "arrow.up.right.circle.fill",
                      achieved: logs.contains { $0.profit > 0 }),
            Milestone(id: "break-even", title: "Broke even",
                      detail: "Total sales cover everything you've spent.", icon: "scalemass.fill",
                      achieved: s.totalRevenue > 0 && s.totalProfit >= 0),
            Milestone(id: "on-pace", title: "On pace with your guess",
                      detail: "Average at least your normal-month guess.", icon: "target",
                      achieved: s.weeks > 0 && s.paceVsGuess >= 1),
            Milestone(id: "month", title: "One month of tracking",
                      detail: "Log 4 weeks.", icon: "calendar",
                      achieved: logs.count >= 4),
        ]
    }
}

// MARK: - Store (saved on the device as JSON)

@Observable
final class BusinessStore {
    private(set) var businesses: [SavedBusiness] = []

    private let fileURL: URL = {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("businesses.json")
    }()

    init() { load() }

    func business(_ id: UUID) -> SavedBusiness? {
        businesses.first { $0.id == id }
    }

    /// Saves a new business, or updates the plan of an existing one. Returns its id.
    @discardableResult
    func save(name: String, idea: String, plan: Assumptions, existingID: UUID?) -> UUID {
        if let id = existingID, let i = businesses.firstIndex(where: { $0.id == id }) {
            businesses[i].plan = plan
            businesses[i].idea = idea
            businesses[i].updatedAt = Date()
            persist()
            return id
        }
        let b = SavedBusiness(name: name, idea: idea, plan: plan)
        businesses.insert(b, at: 0)
        persist()
        return b.id
    }

    func delete(_ id: UUID) {
        businesses.removeAll { $0.id == id }
        persist()
    }

    func addLog(_ log: SalesLog, to id: UUID) {
        guard let i = businesses.firstIndex(where: { $0.id == id }) else { return }
        businesses[i].logs.append(log)
        businesses[i].updatedAt = Date()
        persist()
    }

    func deleteLog(_ logID: UUID, from id: UUID) {
        guard let i = businesses.firstIndex(where: { $0.id == id }) else { return }
        businesses[i].logs.removeAll { $0.id == logID }
        businesses[i].updatedAt = Date()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([SavedBusiness].self, from: data) else { return }
        businesses = saved
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(businesses) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
