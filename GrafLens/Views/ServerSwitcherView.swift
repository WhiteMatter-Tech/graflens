import SwiftUI

struct ServerSwitcherMenu: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        Menu {
            if let active = connectionManager.activeConnection {
                Section("Connected") {
                    Label(active.displayName, systemImage: "checkmark.circle.fill")
                }
            }

            if connectionManager.connections.count > 1 {
                Section("Switch Server") {
                    ForEach(connectionManager.connections.filter { $0.id != connectionManager.activeConnection?.id }) { conn in
                        Button {
                            switchTo(conn)
                        } label: {
                            Label(conn.displayName, systemImage: "server.rack")
                        }
                    }
                }
            }

            Section {
                Button {
                    connectionManager.disconnect()
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.caption)
                Text(connectionManager.activeConnection?.displayName ?? "Server")
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial)
            .clipShape(Capsule())
        }
    }

    private func switchTo(_ connection: ServerConnection) {
        HapticManager.medium()
        Task {
            do {
                try await connectionManager.connect(to: connection)
                HapticManager.success()
            } catch {
                HapticManager.error()
            }
        }
    }
}
