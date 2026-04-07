import SwiftUI

struct RootView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        Group {
            if connectionManager.isConnected {
                MainTabView()
            } else {
                ConnectView()
            }
        }
        .animation(.easeInOut, value: connectionManager.isConnected)
    }
}
