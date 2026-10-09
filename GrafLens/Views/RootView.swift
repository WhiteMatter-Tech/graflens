import SwiftUI

struct RootView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    @EnvironmentObject var favoritesManager: FavoritesManager
    @EnvironmentObject var webAuthManager: WebAuthManager

    var body: some View {
        Group {
            if connectionManager.isConnected {
                MainTabView()
                    .id(connectionManager.activeConnection?.id)
            } else {
                ConnectView()
            }
        }
        .animation(.easeInOut, value: connectionManager.isConnected)
        .onChange(of: connectionManager.activeConnection?.id, initial: true) { _, id in
            favoritesManager.selectConnection(id)
            webAuthManager.selectConnection(id)
        }
    }
}
