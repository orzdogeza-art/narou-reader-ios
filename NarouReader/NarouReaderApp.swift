import SwiftUI

@main
struct NarouReaderApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.colorScheme)
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
