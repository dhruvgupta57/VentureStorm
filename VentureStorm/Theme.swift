import SwiftUI
import UIKit

/// Colors and shared styles. Every color has a light and a dark version,
/// and profit/loss switch to blue/orange in color-blind mode.
enum Theme {
    /// Set by AppSettings. Uses blue/orange instead of green/red for profit/loss.
    static var colorBlindSafe = false

    static let brand = adaptive(light: (0.38, 0.29, 1.00), dark: (0.58, 0.51, 1.00))   // electric purple
    static let sky = adaptive(light: (0.13, 0.62, 0.98), dark: (0.38, 0.76, 1.00))     // bright blue
    static let sun = adaptive(light: (0.96, 0.66, 0.05), dark: (1.00, 0.78, 0.28))     // yellow
    static let ink = adaptive(light: (0.09, 0.09, 0.17), dark: (0.95, 0.95, 0.98))     // main text
    static let background = adaptive(light: (0.96, 0.96, 0.99), dark: (0.05, 0.05, 0.09))
    static let card = adaptive(light: (1.00, 1.00, 1.00), dark: (0.12, 0.12, 0.18))

    private static let green = adaptive(light: (0.05, 0.68, 0.42), dark: (0.22, 0.84, 0.56))
    private static let coral = adaptive(light: (0.95, 0.30, 0.28), dark: (1.00, 0.48, 0.45))
    private static let safeBlue = adaptive(light: (0.00, 0.45, 0.85), dark: (0.36, 0.66, 1.00))
    private static let safeOrange = adaptive(light: (0.88, 0.42, 0.00), dark: (1.00, 0.62, 0.20))

    static var profit: Color { colorBlindSafe ? safeBlue : green }
    static var loss: Color { colorBlindSafe ? safeOrange : coral }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, sky], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func moneyColor(_ value: Double) -> Color { value >= 0 ? profit : loss }

    static func bigNumber(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// A color that switches automatically between light and dark mode.
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

// MARK: - Background

/// Soft background with two color glows at the top.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.brand.opacity(scheme == .dark ? 0.25 : 0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -140, y: -320)
            Circle()
                .fill(Theme.sky.opacity(scheme == .dark ? 0.20 : 0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 160, y: -260)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

struct CardStyle: ViewModifier {
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(tint.map { $0.opacity(scheme == .dark ? 0.16 : 0.10) } ?? .clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder((tint ?? Theme.ink).opacity(tint == nil ? 0.06 : 0.30), lineWidth: 1)
            )
            .shadow(color: Theme.brand.opacity(tint == nil && scheme == .light ? 0.08 : 0), radius: 14, y: 6)
    }
}

extension View {
    func card(tint: Color? = nil) -> some View { modifier(CardStyle(tint: tint)) }
}

/// Small label at the top of a card.
struct CardTitle: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.brand

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(text.uppercased())
        }
        .font(.caption.weight(.heavy))
        .tracking(0.8)
        .foregroundStyle(color)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(enabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
            )
            .shadow(color: Theme.brand.opacity(enabled ? 0.35 : 0), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(Theme.brand.opacity(0.14)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Small colored tag.
struct Pill: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.brand

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Haptics that respect the Settings toggle

struct HapticModifier<T: Equatable>: ViewModifier {
    @Environment(AppSettings.self) private var settings
    let feedback: SensoryFeedback
    let trigger: T

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { _, _ in settings.haptics }
    }
}

extension View {
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(HapticModifier(feedback: feedback, trigger: trigger))
    }
}
