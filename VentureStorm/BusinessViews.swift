import SwiftUI
import Charts

// MARK: - List of saved businesses

struct BusinessListView: View {
    @Environment(BusinessStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Called when the student opens a business in the simulator.
    let onOpen: (SavedBusiness) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.businesses.isEmpty {
                    ContentUnavailableView(
                        "No saved businesses",
                        systemImage: "folder",
                        description: Text("Run a simulation, then tap Save on the Results screen.")
                    )
                } else {
                    List {
                        ForEach(store.businesses) { b in
                            NavigationLink(value: b.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(b.name).font(.headline)
                                    Text(b.logs.isEmpty ? "No sales logged yet" : "\(b.logs.count) week\(b.logs.count == 1 ? "" : "s") logged")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { store.delete(store.businesses[i].id) }
                        }
                    }
                }
            }
            .navigationTitle("My businesses")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                BusinessDetailView(businessID: id, onOpen: onOpen)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - One business: plan, real sales, milestones

struct BusinessDetailView: View {
    @Environment(BusinessStore.self) private var store
    let businessID: UUID
    let onOpen: (SavedBusiness) -> Void
    @State private var showLogSheet = false

    var body: some View {
        ZStack {
            AppBackground()
            if let b = store.business(businessID) {
                ScrollView {
                    VStack(spacing: 16) {
                        planCard(b)
                        trackerCard(b)
                        if !b.logs.isEmpty {
                            comparisonCard(b)
                            historyCard(b)
                        }
                        milestonesCard(b)
                        if !b.logs.isEmpty { logsCard(b) }
                    }
                    .padding(20)
                }
                .sheet(isPresented: $showLogSheet) {
                    LogWeekView(business: b) { log in store.addLog(log, to: b.id) }
                }
            } else {
                ContentUnavailableView("Business not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(store.business(businessID)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Cards

    private func planCard(_ b: SavedBusiness) -> some View {
        let p = b.plan
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Plan", icon: "doc.text")
            if !b.idea.isEmpty {
                Text(b.idea).foregroundStyle(Theme.ink)
            }
            Text("\(p.price.money) price · \(p.unitCost.money) cost per item · \(p.fixedMonthlyCost.money)/month · \(p.demandLikely.whole) customers in a normal month")
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.7))
            Button {
                onOpen(b)
            } label: {
                Label("Open in simulator", systemImage: "bolt.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private func trackerCard(_ b: SavedBusiness) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Real sales", icon: "chart.bar.doc.horizontal")
            Text(b.logs.isEmpty
                 ? "Log each week's real sales to see how your plan holds up."
                 : "Keep logging each week. The more weeks you log, the better the comparison.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.75))
            Button {
                showLogSheet = true
            } label: {
                Label("Log a week", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }

    private func comparisonCard(_ b: SavedBusiness) -> some View {
        let s = TrackerSummary(b)
        let draws = Detective.draws(for: b.plan, seed: 42)
        let planRun = Simulator.run(b.plan, draws: draws)
        let realRun = Tracker.realityPlan(b).map { Simulator.run($0, draws: draws) }

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Plan vs. reality", icon: "arrow.left.arrow.right")

            HStack(spacing: 12) {
                stat("Total profit", (s.totalProfit >= 0 ? "+" : "−") + abs(s.totalProfit).money, Theme.moneyColor(s.totalProfit))
                stat("Weeks logged", "\(s.weeks)", Theme.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Customers per month")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                Text("Real pace: \(s.monthlyPace.whole) · Your guess: \(s.guessedMonthly.whole)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Pill(text: paceText(s.paceVsGuess),
                     icon: s.paceVsGuess >= 1 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                     color: s.paceVsGuess >= 1 ? Theme.profit : Theme.loss)
            }

            if let realRun {
                VStack(alignment: .leading, spacing: 8) {
                    Text("500 futures at your real pace")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)
                    CompareRow(label: "Lose money", before: planRun.chanceOfLoss.outOfTen, after: realRun.chanceOfLoss.outOfTen,
                               improved: realRun.chanceOfLoss == planRun.chanceOfLoss ? nil : realRun.chanceOfLoss < planRun.chanceOfLoss)
                    CompareRow(label: "Run out of cash", before: planRun.chanceOutOfCash.outOfTen, after: realRun.chanceOutOfCash.outOfTen,
                               improved: realRun.chanceOutOfCash == planRun.chanceOutOfCash ? nil : realRun.chanceOutOfCash < planRun.chanceOutOfCash)
                    CompareRow(label: "Typical 12-month profit", before: planRun.median.money, after: realRun.median.money,
                               improved: realRun.median == planRun.median ? nil : realRun.median > planRun.median)
                    Text("Plan → real pace. Same 500 futures, only the customer numbers changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func historyCard(_ b: SavedBusiness) -> some View {
        let points = Tracker.cumulativeProfit(b)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Total profit over time", icon: "chart.line.uptrend.xyaxis")
            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Theme.ink.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(points) { p in
                    LineMark(x: .value("Week", p.date), y: .value("Total profit", p.total))
                        .foregroundStyle(Theme.brand)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Week", p.date), y: .value("Total profit", p.total))
                        .foregroundStyle(Theme.moneyColor(p.total))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(v.money).font(.caption2) }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Total profit over \(points.count) weeks")
            .accessibilityValue("Now \((points.last?.total ?? 0).money)")
        }
        .card()
    }

    private func milestonesCard(_ b: SavedBusiness) -> some View {
        let list = Tracker.milestones(b)
        let done = list.filter(\.achieved).count
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Milestones · \(done) of \(list.count)", icon: "flag.checkered")
            ForEach(list) { m in
                HStack(spacing: 12) {
                    Image(systemName: m.achieved ? "checkmark.circle.fill" : m.icon)
                        .font(.title3)
                        .foregroundStyle(m.achieved ? Theme.profit : Theme.ink.opacity(0.3))
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(m.achieved ? Theme.ink : Theme.ink.opacity(0.5))
                        Text(m.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(m.achieved ? "Done" : "Not yet")
            }
        }
        .card()
    }

    private func logsCard(_ b: SavedBusiness) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Weekly log", icon: "list.bullet")
            ForEach(Array(b.sortedLogs.reversed())) { log in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week of \(log.weekOf.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(log.unitsSold.whole) sold at \(log.pricePerUnit.money) · spent \(log.moneySpent.money)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((log.profit >= 0 ? "+" : "−") + abs(log.profit).money)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.moneyColor(log.profit))
                    Button {
                        store.deleteLog(log.id, from: b.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete this week")
                }
                if log.id != b.sortedLogs.first?.id { Divider() }
            }
        }
        .card()
    }

    // MARK: Helpers

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
            Text(value).font(Theme.bigNumber(28)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paceText(_ ratio: Double) -> String {
        if ratio >= 1 { return "At or above your guess" }
        return "\((ratio).percent) of your guess"
    }
}

// MARK: - Log one week

struct LogWeekView: View {
    let business: SavedBusiness
    let onSave: (SalesLog) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var weekOf = Date()
    @State private var units: Double = 0
    @State private var price: Double = 0
    @State private var spent: Double = 0

    /// Plan-based estimate: cost per item × units + one week of monthly costs.
    private var estimate: Double {
        units * business.plan.unitCost + business.plan.fixedMonthlyCost / TrackerSummary.weeksPerMonth
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Week of", selection: $weekOf, displayedComponents: .date)
                }
                Section("Sales") {
                    field("Items sold", value: $units, isMoney: false)
                    field("Price per item", value: $price, isMoney: true)
                }
                Section {
                    field("Money spent", value: $spent, isMoney: true)
                    Button("Use estimate: \(estimate.money)") { spent = (estimate * 100).rounded() / 100 }
                } header: {
                    Text("Costs")
                } footer: {
                    Text("Everything you spent this week: supplies, fees, ads. The estimate is cost per item × items sold, plus a week of monthly costs.")
                }
                Section {
                    LabeledContent("Profit this week") {
                        Text((units * price - spent).money)
                            .foregroundStyle(Theme.moneyColor(units * price - spent))
                            .bold()
                    }
                }
            }
            .navigationTitle("Log a week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(SalesLog(weekOf: weekOf, unitsSold: max(0, units),
                                        pricePerUnit: max(0, price), moneySpent: max(0, spent)))
                        dismiss()
                    }
                }
            }
            .onAppear { price = business.plan.price }
        }
    }

    private func field(_ title: String, value: Binding<Double>, isMoney: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isMoney { Text("$").foregroundStyle(.secondary) }
            TextField("0", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .decimalKeyboard()
        }
    }
}
