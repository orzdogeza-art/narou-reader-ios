import SwiftUI

@main
struct NarouReaderApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.colorScheme)
                .task { await store.syncIfStale() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task { await store.syncIfStale() }
                    } else if phase == .background {
                        Task { await store.syncNow() }
                    }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("ライブラリ", systemImage: "books.vertical") }
            RankingView()
                .tabItem { Label("ランキング", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
