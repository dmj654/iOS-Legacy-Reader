import SwiftUI

@main
struct LegacyReaderApp: App {
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
                .accentColor(.accentColor)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BookshelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(0)

            SearchView()
                .tabItem { Label("发现", systemImage: "magnifyingglass") }
                .tag(1)

            BookSourceView()
                .tabItem { Label("书源", systemImage: "globe") }
                .tag(2)

            SettingsView()
                .tabItem { Label("我的", systemImage: "gear") }
                .tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openReader)) { _ in
            selectedTab = 0
        }
    }
}

extension Notification.Name {
    static let openReader = Notification.Name("openReader")
}
