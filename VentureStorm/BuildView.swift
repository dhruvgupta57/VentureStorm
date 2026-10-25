import SwiftUI

/// Screen 1: build the business one step at a time.
/// Each step teaches one idea using the student's own numbers, and updates live.
struct BuildView: View {
    @Bindable var model: AppModel
    @State private var goingForward = true

    @State private var showSettings = false
    @State private var showBusinesses = false
    @Environment(AppSettings.self) private var settings

    private let stepCount = 6
    private var step: Int { model.buildStep }
    private var a: Assumptions { model.assumptions }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stepContent
                    }
                    .padding(20)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                    ))
                }
                .scrollDismissesKeyboard(.interactively)

                footer
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings, onDismiss: {
            model.aiConnected = KeychainStore.currentKey() != nil
            settings.colorVersion += 1
        }) {
            SettingsView()
        }
        .sheet(isPresented: $showBusinesses) {
            BusinessListView { business in
                model.open(business)
                showBusinesses = false
            }
        }
    }

    // MARK: Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cloud.bolt.fill")
                        .foregroundStyle(Theme.brandGradient)
                        .accessibilityHidden(true)
                    Text("VentureStorm")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                Text("Step \(step + 1) of \(stepCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Button {
                    showBusinesses = true
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.brand)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("My businesses")
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.brand)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.brand.opacity(0.12))
                    Capsule()
                        .fill(Theme.brandGradient)
                        .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(stepCount))
                        .animation(.spring(duration: 0.4), value: step)
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("Step \(step + 1) of \(stepCount)")
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if step == stepCount - 1 {
                ForEach(a.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.loss)
                }
            }
            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        go(to: step - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 80)
                }

                Button {
                    if step < stepCount - 1 { go(to: step + 1) } else { model.path.append(.predict) }
                } label: {
                    Text(step == stepCount - 1 ? "Make a prediction" : "Next")
                }
                .buttonStyle(PrimaryButtonStyle(enabled: step < stepCount - 1 || a.isValid))
                .disabled(step == stepCount - 1 && !a.isValid)
            }
        }
    }

    private func go(to newStep: Int) {
        goingForward = newStep > step
        withAnimation(.spring(duration: 0.4)) { model.buildStep = newStep }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: ideaStep
        case 1: priceStep
        case 2: monthlyStep
        case 3: cashStep
        case 4: customersStep
        default: sensitivityStep
        }
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(Theme.ink.opacity(0.65))
        }
        .padding(.bottom, 4)
    }

    private var ideaStep: some View {
        Group {
            stepTitle("Your idea", "Describe your business in one sentence to get starting numbers.")

            VStack(alignment: .leading, spacing: 14) {
                TextField("e.g. Custom hoodies for my school, about $25 each",
                          text: $model.idea, axis: .vertical)
                    .font(.title3)
                    .lineLimit(3...5)

                Button {
                    Task { await model.fillFromIdea() }
                } label: {
                    if model.isDrafting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Fill in starting numbers", systemImage: "sparkles")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !model.idea.trimmingCharacters(in: .whitespaces).isEmpty))
                .disabled(model.idea.trimmingCharacters(in: .whitespaces).isEmpty || model.isDrafting)
            }
            .card()

            Label(model.aiConnected ? "AI is on (Groq)." : "AI is off, so starter templates are used. Add a Groq key in Secrets.swift.",
                  systemImage: model.aiConnected ? "sparkles" : "lightbulb")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let summary = model.draftSummary {
                LessonCard(icon: "checkmark.circle.fill", title: "Numbers filled in", text: summary, color: Theme.profit)
            }

            Text("Or tap Next to enter your own numbers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var priceStep: some View {
        Group {
            stepTitle("Price and cost", "What you charge, and what each item costs you.")

            NumberDial(title: "Price per item", value: binding(\.price, .price),
                       range: 0...200, step: 0.5, source: model.sources[.price])
            NumberDial(title: "Cost per item", value: binding(\.unitCost, .unitCost),
                       range: 0...200, step: 0.5, source: model.sources[.unitCost])

            if a.margin > 0 {
                LessonCard(icon: "dollarsign.circle.fill", title: "Margin",
                           text: "You keep \(a.margin.money) from each sale (\(a.price.money) − \(a.unitCost.money)).",
                           color: Theme.profit)
            } else {
                LessonCard(icon: "exclamationmark.triangle.fill", title: "Margin",
                           text: "Each sale loses \((-a.margin).money). Price needs to be higher than cost.",
                           color: Theme.loss)
            }
        }
    }

    private var monthlyStep: some View {
        Group {
            stepTitle("Monthly costs", "Costs you pay every month even with no sales, like apps, fees or rent.")

            NumberDial(title: "Monthly costs", value: binding(\.fixedMonthlyCost, .fixedMonthlyCost),
                       range: 0...2000, step: 5, source: model.sources[.fixedMonthlyCost])

            LessonCard(icon: "square.stack.3d.up.fill", title: "Fixed vs. variable costs",
                       text: "Cost per item goes up with each sale. Monthly costs (\(a.fixedMonthlyCost.money)) stay the same.")

            if let be = a.breakEvenUnits {
                LessonCard(icon: "scalemass.fill", title: "Break-even",
                           text: "You need \(be.rounded(.up).whole) sales a month to stop losing money.",
                           color: Theme.sky)
            } else {
                LessonCard(icon: "scalemass.fill", title: "Break-even",
                           text: "No break-even. Each sale loses money.", color: Theme.loss)
            }
        }
    }

    private var cashStep: some View {
        Group {
            stepTitle("Starting cash", "The money you have before your first sale.")

            NumberDial(title: "Cash to start", value: binding(\.startingCash, .startingCash),
                       range: 0...5000, step: 25, source: model.sources[.startingCash])

            if let months = a.runwayMonthsIfSlow {
                LessonCard(icon: "hourglass", title: "Cash runway",
                           text: "If sales are slow (\(a.lowCustomers.whole) a month), your cash lasts about \(months.formatted(.number.precision(.fractionLength(1)))) months.",
                           color: Theme.sun)
            } else {
                LessonCard(icon: "hourglass", title: "Cash runway",
                           text: "You make money even in a slow month, so cash keeps growing.",
                           color: Theme.profit)
            }
        }
    }

    private var customersStep: some View {
        Group {
            stepTitle("Customers per month", "At \(a.price.money), how many would buy in a slow, normal and great month?")

            NumberDial(title: "Slow month", value: binding(\.demandLow, .demandLow),
                       range: 0...500, step: 1, isMoney: false, compact: true, source: model.sources[.demandLow])
            NumberDial(title: "Normal month", value: binding(\.demandLikely, .demandLikely),
                       range: 0...500, step: 1, isMoney: false, compact: true, source: model.sources[.demandLikely])
            NumberDial(title: "Great month", value: binding(\.demandHigh, .demandHigh),
                       range: 0...500, step: 1, isMoney: false, compact: true, source: model.sources[.demandHigh])

            LessonCard(icon: "dice.fill", title: "Risk",
                       text: "Range: \(a.demandLow.whole)–\(a.demandHigh.whole) customers. A wider range means more uncertainty. The simulation runs 500 futures in this range.",
                       color: Theme.sky)
        }
    }

    private var sensitivityStep: some View {
        Group {
            stepTitle("Price sensitivity", "If you raised your price a little, how many customers would leave?")

            ForEach(PriceSensitivity.allCases) { option in
                let selected = a.sensitivity == option
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        model.assumptions.sensitivity = option
                        model.markStudent(.sensitivity)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: icon(for: option))
                            .font(.title2)
                            .foregroundStyle(selected ? .white : Theme.brand)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(selected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.brand.opacity(0.10))))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.label).font(.headline).foregroundStyle(Theme.ink)
                            Text(option.explanation).font(.footnote).foregroundStyle(Theme.ink.opacity(0.65))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand)
                        }
                    }
                    .card(tint: selected ? Theme.brand : nil)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .haptic(.selection, trigger: selected)
            }

            SourceTag(source: model.sources[.sensitivity])

            LessonCard(icon: "chart.line.downtrend.xyaxis", title: "Price elasticity",
                       text: "A higher price earns more per sale but can lose customers. The simulation accounts for both.",
                       color: Theme.sun)
        }
    }

    private func icon(for option: PriceSensitivity) -> String {
        switch option {
        case .low: return "hand.thumbsup.fill"
        case .medium: return "person.2.fill"
        case .high: return "figure.walk.departure"
        }
    }

    // MARK: Helpers

    /// Edits a number and marks it as the student's own. Changing the price also
    /// means the customer guesses are now "at this price".
    private func binding(_ keyPath: WritableKeyPath<Assumptions, Double>, _ field: Field) -> Binding<Double> {
        Binding(
            get: { model.assumptions[keyPath: keyPath] },
            set: { newValue in
                model.assumptions[keyPath: keyPath] = newValue
                if field == .price { model.assumptions.referencePrice = newValue }
                model.markStudent(field)
            }
        )
    }
}
