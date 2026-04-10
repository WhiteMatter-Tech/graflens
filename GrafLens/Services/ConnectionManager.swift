import Foundation
import SwiftUI

@MainActor
class ConnectionManager: ObservableObject {
    @Published var connections: [ServerConnection] = []
    @Published var activeConnection: ServerConnection?
    @Published var isConnected = false

    private let connectionsKey = "savedConnections"
    private let activeConnectionKey = "activeConnectionID"

    var apiClient: GrafanaAPIClient? {
        guard let connection = activeConnection else { return nil }
        return GrafanaAPIClient(connection: connection)
    }

    init() {
        loadConnections()
    }

    func addConnection(_ connection: ServerConnection) {
        connections.append(connection)
        saveConnections()
    }

    func updateConnection(_ connection: ServerConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            if activeConnection?.id == connection.id {
                activeConnection = connection
            }
            saveConnections()
        }
    }

    func removeConnection(_ connection: ServerConnection) {
        connections.removeAll { $0.id == connection.id }
        if activeConnection?.id == connection.id {
            activeConnection = nil
            isConnected = false
        }
        saveConnections()
    }

    func connect(to connection: ServerConnection) async throws {
        let client = GrafanaAPIClient(connection: connection)
        _ = try await client.checkHealth()
        activeConnection = connection
        isConnected = true
        UserDefaults.standard.set(connection.id.uuidString, forKey: activeConnectionKey)

        // Share with widget
        SharedDataManager.saveActiveConnection(connection)

        if !connections.contains(where: { $0.id == connection.id }) {
            addConnection(connection)
        }
    }

    func disconnect() {
        activeConnection = nil
        isConnected = false
        UserDefaults.standard.removeObject(forKey: activeConnectionKey)
    }

    // MARK: - Persistence

    private func saveConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: connectionsKey)
        }
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: connectionsKey),
              let saved = try? JSONDecoder().decode([ServerConnection].self, from: data) else {
            return
        }
        connections = saved

        if let activeID = UserDefaults.standard.string(forKey: activeConnectionKey),
           let uuid = UUID(uuidString: activeID),
           let connection = connections.first(where: { $0.id == uuid }) {
            activeConnection = connection
            isConnected = true
            // Keep the shared App Group container in sync so the widget
            // can read the active connection on timeline refresh.
            SharedDataManager.saveActiveConnection(connection)
        }
    }
}
