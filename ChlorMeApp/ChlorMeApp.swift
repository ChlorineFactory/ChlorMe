import SwiftUI
import ChlorCore

@main
struct ChlorMeApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .preferredColorScheme(themeMode.colorScheme)
                .task {
                    await store.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    store.handleScenePhaseChange(newPhase)
                }
        }
    }

    private var themeMode: ChlorThemeMode {
        ChlorThemeMode(rawValue: store.settings.themeMode) ?? .darkGlass
    }
}
