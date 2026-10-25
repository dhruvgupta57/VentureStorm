import SwiftUI

/// A short lesson that uses the student's own numbers. Updates live.
struct LessonCard: View {
    let icon: String
    let title: String
    let text: String
    var color: Color = Theme.brand

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink.opacity(0.8))
            }
        }
        .card(tint: color)
        .accessibilityElement(children: .combine)
    }
}

/// Shows where a number came from (AI or starter template) until the student edits it.
struct SourceTag: View {
    let source: NumberSource?

    var body: some View {
        switch source {
        case .aiGuess(let reason):
            Label("AI guess: \(reason)", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.orange)
        case .starterGuess(let reason):
            Label("Starter guess: \(reason)", systemImage: "lightbulb")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

/// Big number with − / + buttons and a slider. Tap the number to type.
struct NumberDial: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var isMoney = true
    var compact = false
    var source: NumberSource? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            Text(title)
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(Theme.ink.opacity(0.7))

            HStack {
                roundButton("minus", label: "Decrease \(title)") { value = max(range.lowerBound, value - step) }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if isMoney {
                        Text("$").font(Theme.bigNumber(compact ? 22 : 30)).foregroundStyle(Theme.brand)
                    }
                    TextField("0", value: $value, format: .number)
                        .font(Theme.bigNumber(compact ? 32 : 48))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                        .decimalKeyboard()
                        .accessibilityLabel(title)
                }
                Spacer()
                roundButton("plus", label: "Increase \(title)") { value = min(range.upperBound, value + step) }
            }

            Slider(value: Binding(
                get: { min(max(value, range.lowerBound), range.upperBound) },
                set: { value = ($0 / step).rounded() * step }
            ), in: range)
            .tint(Theme.brand)
            .accessibilityLabel(title)
            .accessibilityValue(isMoney ? value.money : value.whole)

            SourceTag(source: source)
        }
        .card()
        .haptic(.selection, trigger: value)
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.brand)
                .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                .background(Circle().fill(Theme.brand.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Ten dots, some colored. Shows "X in 10 futures" at a glance.
struct TenDotMeter: View {
    let chance: Double
    let color: Color

    /// At least one dot when it happened at all, matching the "<1" text.
    var filled: Int { chance > 0 ? max(1, Int((chance * 10).rounded())) : 0 }

    var body: some View {
        // Dots shrink to fit the space they're given, so the meter never pushes the screen wider.
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { i in
                Circle()
                    .fill(i < filled ? color : color.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chance.tenthsText) in 10 futures")
    }
}

/// "Before → after" row.
struct CompareRow: View {
    let label: String
    let before: String
    let after: String
    var improved: Bool? = nil

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.ink.opacity(0.7))
            Spacer()
            Text(before).font(.subheadline).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(.secondary)
            Text(after)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(improved == true ? Theme.profit : (improved == false ? Theme.loss : Theme.ink))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(before) before, \(after) after")
    }
}

/// Before/after rows for two simulation runs. Green = better, red = worse.
struct BeforeAfter: View {
    let before: SimSummary
    let after: SimSummary

    var body: some View {
        VStack(spacing: 10) {
            CompareRow(label: "Average profit", before: before.meanProfit.money, after: after.meanProfit.money,
                       improved: compare(after.meanProfit, before.meanProfit, higherIsBetter: true))
            CompareRow(label: "Lose money", before: before.chanceOfLoss.outOfTen, after: after.chanceOfLoss.outOfTen,
                       improved: compare(after.chanceOfLoss, before.chanceOfLoss, higherIsBetter: false))
            CompareRow(label: "Run out of cash", before: before.chanceOutOfCash.outOfTen, after: after.chanceOutOfCash.outOfTen,
                       improved: compare(after.chanceOutOfCash, before.chanceOutOfCash, higherIsBetter: false))
        }
    }

    private func compare(_ new: Double, _ old: Double, higherIsBetter: Bool) -> Bool? {
        if abs(new - old) < 0.0001 { return nil }
        return higherIsBetter ? new > old : new < old
    }
}

extension View {
    /// Number keyboard (with a return key and minus sign) on iPhone.
    @ViewBuilder
    func decimalKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}
