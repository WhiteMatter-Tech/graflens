import Foundation

/// Shared data access between main app and widget extension via App Groups
enum SharedDataManager {
    static let appGroupID = "group.tech.whitematter.graflens"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func scope(_ connectionID: UUID? = nil) -> String {
        (connectionID ?? loadActiveConnection()?.id)?.uuidString ?? "disconnected"
    }
    static func clearActiveConnection() { sharedDefaults?.removeObject(forKey: "widgetActiveConnection") }

    // MARK: - Connection

    static func saveActiveConnection(_ connection: ServerConnection) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(connection) {
            defaults.set(data, forKey: "widgetActiveConnection")
        }
    }

    static func loadActiveConnection() -> ServerConnection? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "widgetActiveConnection"),
              let connection = try? JSONDecoder().decode(ServerConnection.self, from: data) else { return nil }
        return connection
    }

    // MARK: - Widget Panel Selections

    static func saveWidgetPanel(widgetID: String, dashboardUID: String, dashboardTitle: String, panelID: Int, panelTitle: String) {
        guard let defaults = sharedDefaults else { return }
        let selection = WidgetPanelSelection(
            dashboardUID: dashboardUID,
            dashboardTitle: dashboardTitle,
            panelID: panelID,
            panelTitle: panelTitle
        )
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: "widgetPanel_\(widgetID)")
        }
    }

    static func loadWidgetPanel(widgetID: String) -> WidgetPanelSelection? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "widgetPanel_\(widgetID)"),
              let selection = try? JSONDecoder().decode(WidgetPanelSelection.self, from: data) else { return nil }
        return selection
    }

    // MARK: - Cache dashboard/panel list for widget config

    static func cacheDashboardList(_ dashboards: [DashboardSearchResult], connectionID: UUID) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(dashboards) {
            defaults.set(data, forKey: "cachedDashboards_" + scope(connectionID))
        }
    }

    static func loadCachedDashboards() -> [DashboardSearchResult] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "cachedDashboards_" + scope()),
              let dashboards = try? JSONDecoder().decode([DashboardSearchResult].self, from: data) else { return [] }
        return dashboards
    }

    static func cachePanelList(dashboardUID: String, panels: [PanelInfo], connectionID: UUID) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(panels) {
            defaults.set(data, forKey: "cachedPanels_\(scope(connectionID))_\(dashboardUID)")
        }
    }

    static func loadCachedPanels(dashboardUID: String, connectionID: UUID? = nil) -> [PanelInfo] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "cachedPanels_\(scope(connectionID))_\(dashboardUID)"),
              let panels = try? JSONDecoder().decode([PanelInfo].self, from: data) else { return [] }
        return panels
    }

    // MARK: - Panel Snapshots (file-based, shared via App Group container)

    private static var snapshotDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("PanelSnapshots", isDirectory: true)
    }

    private static func snapshotURL(connectionID: UUID, dashboardUID: String, panelID: Int, from: String, theme: String) -> URL? {
        // Encode arbitrary dashboard UIDs without making them filesystem path components.
        let key = "\(connectionID.uuidString)|\(dashboardUID)|\(panelID)|\(from)|\(theme)"
        let filename = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return snapshotDirectory?.appendingPathComponent(filename + ".json")
    }

    struct CachedSnapshot: Codable {
        let imageData: Data
        let capturedAt: Date
    }

    static func savePanelSnapshot(connectionID: UUID, dashboardUID: String, panelID: Int, from: String, theme: String, imageData: Data) {
        guard let dir = snapshotDirectory,
              let url = snapshotURL(connectionID: connectionID, dashboardUID: dashboardUID, panelID: panelID, from: from, theme: theme) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshot = CachedSnapshot(imageData: imageData, capturedAt: Date())
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }

    static func loadPanelSnapshot(connectionID: UUID, dashboardUID: String, panelID: Int, from: String, theme: String) -> CachedSnapshot? {
        guard let url = snapshotURL(connectionID: connectionID, dashboardUID: dashboardUID, panelID: panelID, from: from, theme: theme),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(CachedSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.capturedAt) >= 0,
              Date().timeIntervalSince(snapshot.capturedAt) < 15 * 60 else { return nil }
        return snapshot
    }
}

// MARK: - Shared types

struct WidgetPanelSelection: Codable {
    let dashboardUID: String
    let dashboardTitle: String
    let panelID: Int
    let panelTitle: String
}

struct PanelInfo: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let type: String?
    let datasourceUID: String?
    let datasourceType: String?
    let targets: [PanelInfoTarget]?
}

struct PanelInfoTarget: Codable, Hashable {
    let refId: String
    let expr: String?
    let rawSql: String?
}
