import SwiftUI

@main
struct GrafLensApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var webAuthManager = WebAuthManager()
    @StateObject private var storeManager = StoreManager()
    @StateObject private var appearanceManager = AppearanceManager()
    @StateObject private var favoritesManager = FavoritesManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connectionManager)
                .environmentObject(webAuthManager)
                .environmentObject(storeManager)
                .environmentObject(appearanceManager)
                .environmentObject(favoritesManager)
                .preferredColorScheme(appearanceManager.mode.colorScheme)
        }
    }
}
