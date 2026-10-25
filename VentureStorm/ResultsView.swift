import SwiftUI
import Charts

/// Screen 3: results across 500 futures and the biggest driver.
struct ResultsView: View {
    @Bindable var model: AppModel
    @Environment(BusinessStore.self) private var store
    @State private var askName = false
    @State private var nameText = ""
    @State private var savedNote: String?

    var body: some View {
        ZStack {
            AppBackground()
            if let report = model.report {
                ScrollView {
                    VStack(spacing: 16) {
                        content(report)
                    }
                    .padding(20)
                }
                .id(report.seed.description + report.summary.meanProfit.description)
            } else {
                ContentUnavailableView("No results yet", systemImage: "chart.bar")
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Name this business", isPresented: $askName) {
            TextField("Name", text: $nameText)
            Button("Save") { save(name: nameText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved businesses are in the folder on the first screen. You can track real sales there.")
        }
    }

    // MARK: Saving

    private var currentName: String? {
        model.currentBusinessID.flatMap { store.business($0)?.name }
    }

    private var saveLabel: String {
        if let name = currentName { return "Save changes to \(name)" }
        return "Save this business"
    }

    private func saveTapped() {
        if currentName != nil {
            save(name: currentName ?? "")
        } else {
            let idea = model.idea.trimmingCharacters(in: .whitespacesAndNewlines)
            nameText = idea.isEmpty ? "My business" : String(idea.prefix(30))
            askName = true
        }
    }

    private func save(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = store.save(name: trimmed.isEmpty ? "My business" : trimmed,
                            idea: model.idea,
                            plan: model.assumptions,
                            existingID: model.currentBusinessID)
        model.currentBusinessID = id
        savedNote = "Saved. Open the folder on the first screen to track real sales."
    }

    @ViewBuilder
    private func content(_ r: AnalysisReport) -> some View {
        let s = r.summary

        if let before = model.beforeFix, let title = model.appliedFixTitle {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(text: "After fix", icon: "wrench.and.screwdriver.fill", color: Theme.profit)
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                BeforeAfter(before: before.summary, after: s)
            }
            .card(tint: Theme.profit)
        }

        HeroResultCard(summary: s, prediction: model.prediction, months: r.assumptions.months)

        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "\(s.outcomes.count) possible futures", icon: "point.3.filled.connected.trianglepath.dotted")
            Text("Cash by month")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            FuturesChart(summary: s)
                .frame(height: 220)
            Text("The chart shows a sample. All numbers use all \(s.outcomes.count) futures.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                legend(Theme.profit, "Stayed above $0")
                legend(Theme.loss, "Ran out")
                legend(Theme.brand, "Typical")
            }
            .font(.caption)
        }
        .card()

        HStack(spacing: 12) {
            riskTile(title: "Lose money", chance: s.chanceOfLoss, color: Theme.loss)
            riskTile(title: "Run out of cash", chance: s.chanceOutOfCash, color: Theme.sun)
        }

        if let be = r.assumptions.breakEvenUnits {
            HStack(spacing: 12) {
                statTile(title: "Break-even", value: "\(be.rounded(.up).whole)", unit: "sales/month", color: Theme.sky)
                statTile(title: "You expect", value: r.assumptions.likelyCustomers.whole, unit: "sales/month",
                         color: r.assumptions.likelyCustomers >= be ? Theme.profit : Theme.loss)
            }
        }

        if let top = r.weakestGuess {
            WeakestGuessCard(report: r, top: top)

            VStack(alignment: .leading, spacing: 8) {
                CardTitle(text: "Real-world test", icon: "checkmark.seal.fill", color: Theme.sun)
                Text(top.driver.realWorldTest)
                    .foregroundStyle(Theme.ink)
            }
            .card(tint: Theme.sun)
        }

        VStack(spacing: 10) {
            Button {
                model.path.append(.fixIt)
            } label: {
                Label("Open Fix-It Coach", systemImage: "wrench.and.screwdriver.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                withAnimation { model.tryNewFutures() }
            } label: {
                Label("Run with a new seed", systemImage: "shuffle")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                saveTapped()
            } label: {
                Label(saveLabel, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SecondaryButtonStyle())

            if let savedNote {
                Label(savedNote, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.profit)
            }

            Text("Seed \(r.seed). The same seed gives the same results.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func riskTile(title: String, chance: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(chance.tenthsText).font(Theme.bigNumber(34)).foregroundStyle(Theme.ink)
                Text("in 10").font(.caption).foregroundStyle(.secondary)
            }
            TenDotMeter(chance: chance, color: color)
        }
        .card()
    }

    private func statTile(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(Theme.bigNumber(34)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .card()
    }
}

// MARK: - Hero card with count-up and prediction check

struct HeroResultCard: View {
    let summary: SimSummary
    let prediction: Prediction
    let months: Int

    @State private var shown: Double = 0
    @State private var revealed = false

    private var madeMoney: Bool { summary.median > 0 }
    private var color: Color { Theme.moneyColor(summary.median) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Typical result · \(months) months", icon: "chart.line.uptrend.xyaxis")

            Text((shown >= 0 ? "+" : "−") + abs(shown).money)
                .accessibilityLabel("Typical result: \(summary.median >= 0 ? "profit" : "loss") of \(abs(summary.median).money)")
                .font(Theme.bigNumber(54))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: shown))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("Range \(summary.p10.money) to \(summary.p90.money)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if revealed {
                verdict
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .card()
        .haptic(madeMoney ? .success : .warning, trigger: revealed)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { shown = summary.median }
            withAnimation(.spring(duration: 0.5).delay(1.0)) { revealed = true }
        }
    }

    @ViewBuilder
    private var verdict: some View {
        let right: Bool? = {
            switch prediction.outcome {
            case .profit: return madeMoney
            case .loss: return !madeMoney
            case .unsure: return nil
            }
        }()

        VStack(alignment: .leading, spacing: 6) {
            switch right {
            case .some(true):
                Pill(text: "Prediction correct", icon: "checkmark.circle.fill", color: Theme.profit)
            case .some(false):
                Pill(text: "Prediction incorrect", icon: "xmark.circle.fill", color: Theme.loss)
            case .none:
                Pill(text: "No prediction made", icon: "questionmark.circle.fill", color: Theme.sky)
            }
            if let guess = prediction.guessTotalProfit {
                Text("You guessed \(guess.money), off by \(abs(guess - summary.median).money).")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink.opacity(0.7))
            }
        }
    }
}

// MARK: - 500 futures chart

/// Cash over time for a sample of futures. Green stayed above $0, red ran out,
/// and the bold line is the typical future. Draws in from left to right.
struct FuturesChart: View {
    let summary: SimSummary
    @State private var progress: CGFloat = 0

    /// Up to 120 evenly spaced futures, so the chart stays fast.
    private var sample: [ScenarioOutcome] {
        let all = summary.outcomes
        let stride = max(1, all.count / 120)
        return Swift.stride(from: 0, to: all.count, by: stride).map { all[$0] }
    }

    var body: some View {
        let typical = summary.typicalOutcome

        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Theme.ink.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(sample) { future in
                ForEach(Array(future.cashPath.enumerated()), id: \.offset) { month, cash in
                    LineMark(
                        x: .value("Month", month),
                        y: .value("Cash", cash),
                        series: .value("Future", "f\(future.id)")
                    )
                    .foregroundStyle((future.ranOutOfCash ? Theme.loss : Theme.profit).opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.monotone)
                }
            }

            if let typical {
                ForEach(Array(typical.cashPath.enumerated()), id: \.offset) { month, cash in
                    LineMark(
                        x: .value("Month", month),
                        y: .value("Cash", cash),
                        series: .value("Future", "typical")
                    )
                    .foregroundStyle(Theme.brand)
                    .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
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
        .chartXAxis {
            AxisMarks(values: .stride(by: 3)) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) { Text("M\(m)").font(.caption2) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cash over time in \(summary.outcomes.count) futures")
        .accessibilityValue("Cash runs out in \(summary.chanceOutOfCash.outOfTen) futures. In a typical future you end with \((summary.typicalOutcome?.endingCash ?? 0).money).")
        .mask(alignment: .leading) {
            GeometryReader { geo in
                Rectangle().frame(width: geo.size.width * progress)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4)) { progress = 1 }
        }
    }
}

// MARK: - Biggest driver

struct WeakestGuessCard: View {
    let report: AnalysisReport
    let top: SensitivityResult
    @State private var grow = false

    var body: some View {
        let maxSwing = max(report.sensitivities.map(\.swing).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Assumption Detective", icon: "magnifyingglass")
            Text("Biggest driver: \(top.driver.name)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.ink)
            Text(Detective.weakestGuessText(report))
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.75))

            VStack(spacing: 10) {
                ForEach(report.sensitivities) { item in
                    let isTop = item.driver == top.driver
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.driver.name).font(.subheadline.weight(isTop ? .bold : .regular))
                            Spacer()
                            Text(item.swing.money).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .foregroundStyle(Theme.ink)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.ink.opacity(0.06))
                                Capsule()
                                    .fill(isTop ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.ink.opacity(0.22)))
                                    .frame(width: grow ? geo.size.width * item.swing / maxSwing : 0)
                            }
                        }
                        .frame(height: 10)
                        Text("Tested: \(item.driver.rangeText)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.driver.name): changes average profit by \(item.swing.money), tested \(item.driver.rangeText)")
                }
            }
            .padding(.top, 4)

            Text("Each input is changed by itself on the same 500 futures. The ranking depends on the ranges tested.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
        .onAppear {
            withAnimation(.spring(duration: 0.9).delay(0.3)) { grow = true }
        }
    }
}
