import SwiftUI
import Observation

// MARK: - Options

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum TextSize: String, CaseIterable, Identifiable {
    case system, large, extraLarge
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match iPhone"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }

    /// Text sizes allowed. "Match iPhone" follows the phone's own text size setting.
    var range: ClosedRange<DynamicTypeSize> {
        switch self {
        case .system: return .xSmall ... .accessibility2
        case .large: return .xxLarge ... .xxLarge
        case .extraLarge: return .accessibility1 ... .accessibility1
        }
    }
}

// MARK: - Saved settings

/// App settings, saved on the device so they stay after the app closes.
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    var textSize: TextSize {
        didSet { defaults.set(textSize.rawValue, forKey: "textSize") }
    }
    var colorBlindSafe: Bool {
        didSet {
            defaults.set(colorBlindSafe, forKey: "colorBlindSafe")
            Theme.colorBlindSafe = colorBlindSafe
        }
    }
    var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: "reduceMotion") }
    }
    var haptics: Bool {
        didSet { defaults.set(haptics, forKey: "haptics") }
    }

    /// Changes when the colors change, so screens redraw with the new colors.
    var colorVersion = 0

    init() {
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        textSize = TextSize(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .system
        colorBlindSafe = defaults.bool(forKey: "colorBlindSafe")
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        Theme.colorBlindSafe = colorBlindSafe
    }
}

// MARK: - Settings screen

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var hasKey = false
    @State private var keyStatus: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Text size", selection: $settings.textSize) {
                        ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Text")
                } footer: {
                    Text("\"Match iPhone\" follows the text size in your iPhone's Settings.")
                }

                Section {
                    Toggle(isOn: $settings.colorBlindSafe) {
                        Label("Color-blind friendly colors", systemImage: "eye")
                    }
                    HStack(spacing: 16) {
                        swatch(settings.colorBlindSafe ? "Profit (blue)" : "Profit (green)", Theme.profit)
                        swatch(settings.colorBlindSafe ? "Loss (orange)" : "Loss (red)", Theme.loss)
                    }
                    .accessibilityHidden(true)

                    Toggle(isOn: $settings.reduceMotion) {
                        Label("Reduce motion", systemImage: "figure.walk.motion")
                    }
                    Toggle(isOn: $settings.haptics) {
                        Label("Haptics", systemImage: "hand.tap")
                    }
                } header: {
                    Text("Accessibility")
                } footer: {
                    Text("Color-blind mode uses blue and orange instead of green and red. Reduce motion turns off animations. VoiceOver reads out the charts, meters and buttons.")
                }

                Section {
                    SecureField(hasKey ? "Replace saved key" : "Groq API key", text: $keyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") { saveKey() }
                        .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button("Remove key", role: .destructive) {
                            KeychainStore.deleteKey()
                            hasKey = false
                            keyStatus = "Key removed. AI is off."
                        }
                    }
                    if let keyStatus {
                        Text(keyStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("Get a free key at console.groq.com. Put it in Secrets.swift, or paste it here to save it in this iPhone's Keychain. With AI on, your idea and results are sent to Groq to write starting numbers and hints. Without a key, the app uses starter templates.")
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    Text("All numbers come from the simulation. AI is only used for wording and suggestions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                hasKey = KeychainStore.readKey() != nil
                if KeychainStore.keyIsInCode {
                    keyStatus = "AI is on, using the key in Secrets.swift."
                } else {
                    keyStatus = hasKey ? "AI is on." : "AI is off."
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func saveKey() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.saveKey(key)
        keyText = ""
        hasKey = true
        keyStatus = "Checking key…"
        Task {
            let works = await GroqAI(apiKey: key).test()
            keyStatus = works ? "Key works. AI is on." : "Key saved, but the test failed. Check the key and your internet."
        }
    }

    private func swatch(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 14, height: 14)
            Text(text).font(.footnote)
        }
    }
}
