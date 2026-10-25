import SwiftUI

/// Screen 4: a chat-style coach. The engine finds the problem, the coach gives hints,
/// and every fix shown has already been tested by the simulation.
struct FixItView: View {
    @Bindable var model: AppModel
    @State private var appliedCount = 0

    var body: some View {
        ZStack {
            AppBackground()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let problem = model.problem {
                            problemCard(problem)
                            chat
                            if model.hintLevel >= 3 { fixes }
                            Color.clear.frame(height: 1).id("bottom")
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Analyzing…").foregroundStyle(.secondary)
                            }
                            .card()
                        }
                    }
                    .padding(20)
                }
                .onChange(of: model.hintLevel) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .navigationTitle("Fix-It Coach")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.success, trigger: appliedCount)
        .task {
            if model.problem == nil { await model.prepareCoach() }
        }
    }

    // MARK: Problem

    private func problemCard(_ problem: Problem) -> some View {
        let healthy = problem.kind == .healthy
        let color = healthy ? Theme.profit : Theme.loss

        return VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: healthy ? "No major problems" : "Main problem",
                      icon: healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                      color: color)
            Text(problem.title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.ink)
            Text(problem.detail).foregroundStyle(Theme.ink.opacity(0.8))
        }
        .card(tint: color)
    }

    // MARK: Chat

    private var chat: some View {
        VStack(alignment: .leading, spacing: 12) {
            coachBubble("Try to find the cause before viewing the fixes.")

            ForEach(Array(model.hints.prefix(min(model.hintLevel, 2)).enumerated()), id: \.offset) { index, hint in
                studentBubble(index == 0 ? "Hint" : "Another hint")
                coachBubble(hint)
            }

            if model.hintLevel >= 3 {
                studentBubble("Show fixes")
                coachBubble(model.fixes.isEmpty
                    ? "None of the tested fixes improved the result. The plan needs a bigger change."
                    : "Each fix was tested on the same 500 futures. Only fixes that improved the result are shown.")
            }

            if model.hintLevel < 3 {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.4)) { model.hintLevel += 1 }
                    } label: {
                        Text(model.hintLevel == 0 ? "Hint" : (model.hintLevel == 1 ? "Another hint" : "Show fixes"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.brand)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().strokeBorder(Theme.brand, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.usedAIWords {
                Text("Hints written by AI. Numbers checked against the simulation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func coachBubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.brandGradient))
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Theme.ink)
                .padding(12)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4,
                                           bottomTrailingRadius: 18, topTrailingRadius: 18)
                        .fill(Theme.card)
                        .shadow(color: Theme.brand.opacity(0.08), radius: 8, y: 3)
                )
            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach: \(text)")
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private func studentBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 4, topTrailingRadius: 18)
                        .fill(Theme.brandGradient)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: Fixes

    @ViewBuilder
    private var fixes: some View {
        ForEach(Array(model.fixes.enumerated()), id: \.element.id) { index, fix in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Pill(text: index == 0 ? "Best fix" : "Option \(index + 1)",
                         icon: index == 0 ? "star.fill" : nil,
                         color: index == 0 ? Theme.profit : Theme.brand)
                    Spacer()
                    Pill(text: "Tested", icon: "checkmark.seal.fill", color: Theme.sky)
                }
                Text(fix.title)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.ink)
                Text(model.fixNotes[fix.id] ?? fix.howToDoIt)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink.opacity(0.75))

                BeforeAfter(before: fix.before, after: fix.after)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.background))

                Label(fix.tradeoff, systemImage: "arrow.left.arrow.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    appliedCount += 1
                    model.apply(fix)
                } label: {
                    Label("Apply and re-run", systemImage: "bolt.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .card()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if let top = model.report?.weakestGuess {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(text: "Real-world test", icon: "checkmark.seal.fill", color: Theme.sun)
                Text(top.driver.realWorldTest).foregroundStyle(Theme.ink)
            }
            .card(tint: Theme.sun)
        }
    }
}
