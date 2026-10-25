import SwiftUI

/// Screen 2: the student predicts the result before seeing it.
struct PredictView: View {
    @Bindable var model: AppModel
    @State private var running = false
    @State private var futuresShown = 0

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prediction")
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.ink)
                        Text("Guess the result before running the simulation.")
                            .foregroundStyle(Theme.ink.opacity(0.65))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        CardTitle(text: "Over \(model.assumptions.months) months, will you…", icon: "questionmark.circle")
                        ForEach(ProfitPrediction.allCases) { option in
                            choiceButton(option)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        CardTitle(text: "Total profit guess (optional)", icon: "target")
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("$").font(Theme.bigNumber(30)).foregroundStyle(Theme.brand)
                            TextField("1,500", value: $model.prediction.guessTotalProfit, format: .number)
                                .font(Theme.bigNumber(44))
                                .foregroundStyle(Theme.ink)
                                .decimalKeyboard()
                        }
                        Text("Use a minus sign for a loss, like -200.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .card()
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    run()
                } label: {
                    Label("Run 500 futures", systemImage: "bolt.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            if running { runningOverlay }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choiceButton(_ option: ProfitPrediction) -> some View {
        let selected = model.prediction.outcome == option
        let color: Color = option == .profit ? Theme.profit : (option == .loss ? Theme.loss : Theme.sky)
        let icon = option == .profit ? "arrow.up.right.circle.fill" : (option == .loss ? "arrow.down.right.circle.fill" : "questionmark.circle.fill")

        return Button {
            withAnimation(.spring(duration: 0.3)) { model.prediction.outcome = option }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(color).accessibilityHidden(true)
                Text(option.rawValue).font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.headline).foregroundStyle(color) }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? color.opacity(0.16) : Theme.ink.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .haptic(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Short "simulating" moment before the results appear.
    private var runningOverlay: some View {
        ZStack {
            Theme.background.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "cloud.bolt.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.brandGradient)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Running \(futuresShown) futures…")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: Double(futuresShown)))
                Text("Each future uses different random demand.")
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
    }

    private func run() {
        withAnimation { running = true }
        futuresShown = 0
        Task {
            for n in stride(from: 50, through: 500, by: 50) {
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.snappy) { futuresShown = n }
            }
            model.startFresh()
            model.path.append(.results)
            try? await Task.sleep(for: .milliseconds(300))
            running = false
        }
    }
}
