import Foundation

/// Shared data access between main app and widget extension via App Groups
enum SharedDataManager {
    static let appGroupID = "group.tech.whitematter.graflens"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

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

    static func cacheDashboardList(_ dashboards: [DashboardSearchResult]) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(dashboards) {
            defaults.set(data, forKey: "cachedDashboards")
        }
    }

    static func loadCachedDashboards() -> [DashboardSearchResult] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "cachedDashboards"),
              let dashboards = try? JSONDecoder().decode([DashboardSearchResult].self, from: data) else { return [] }
        return dashboards
    }

    static func cachePanelList(dashboardUID: String, panels: [PanelInfo]) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(panels) {
            defaults.set(data, forKey: "cachedPanels_\(dashboardUID)")
        }
    }

    static func loadCachedPanels(dashboardUID: String) -> [PanelInfo] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "cachedPanels_\(dashboardUID)"),
              let panels = try? JSONDecoder().decode([PanelInfo].self, from: data) else { return [] }
        return panels
    }

    // MARK: - Panel Snapshots (file-based, shared via App Group container)

    private static var snapshotDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("PanelSnapshots", isDirectory: true)
    }

    private static func snapshotURL(dashboardUID: String, panelID: Int) -> URL? {
        snapshotDirectory?.appendingPathComponent("\(dashboardUID)_\(panelID).jpg")
    }

    static func savePanelSnapshot(dashboardUID: String, panelID: Int, imageData: Data) {
        guard let dir = snapshotDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let url = snapshotURL(dashboardUID: dashboardUID, panelID: panelID) else { return }
        try? imageData.write(to: url)
    }

    static func loadPanelSnapshot(dashboardUID: String, panelID: Int) -> Data? {
        guard let url = snapshotURL(dashboardUID: dashboardUID, panelID: panelID) else { return nil }
        return try? Data(contentsOf: url)
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
