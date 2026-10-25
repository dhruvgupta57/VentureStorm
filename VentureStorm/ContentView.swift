import SwiftUI

/// App flow: Build → Predict → Results → Fix-It Coach → (apply fix) → Results.
struct ContentView: View {
    @State private var model = AppModel()
    @State private var settings = AppSettings()
    @State private var store = BusinessStore()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var noMotion: Bool { settings.reduceMotion || systemReduceMotion }

    var body: some View {
        let off = noMotion

        NavigationStack(path: $model.path) {
            BuildView(model: model)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .predict: PredictView(model: model)
                    case .results: ResultsView(model: model)
                    case .fixIt: FixItView(model: model)
                    }
                }
        }
        .id(settings.colorVersion)                       // redraw when color-blind mode changes
        .environment(settings)
        .environment(store)
        .tint(Theme.brand)
        .preferredColorScheme(settings.appearance.colorScheme)
        .dynamicTypeSize(settings.textSize.range)
        .transaction { t in
            if off {
                t.animation = nil
                t.disablesAnimations = true
            }
        }
    }
}

#Preview {
    ContentView()
}
