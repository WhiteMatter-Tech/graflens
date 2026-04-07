import AppIntents
import SwiftUI

// MARK: - Check Alerts Intent

struct CheckAlertsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Grafana Alerts"
    static var description = IntentDescription("Check for firing alerts on your Grafana instance")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let data = UserDefaults.standard.data(forKey: "savedConnections"),
              let connections = try? JSONDecoder().decode([ServerConnection].self, from: data),
              let activeID = UserDefaults.standard.string(forKey: "activeConnectionID"),
              let uuid = UUID(uuidString: activeID),
              let connection = connections.first(where: { $0.id == uuid }) else {
            return .result(value: "No active Grafana connection")
        }

        let client = GrafanaAPIClient(connection: connection)
        do {
            let alerts = try await client.getFiringAlerts()
            let firing = alerts.filter { $0.state?.lowercased() == "firing" }
            if firing.isEmpty {
                return .result(value: "All clear — no firing alerts")
            } else {
                let names = firing.prefix(5).map { $0.alertName }.joined(separator: ", ")
                return .result(value: "\(firing.count) firing alert\(firing.count == 1 ? "" : "s"): \(names)")
            }
        } catch {
            return .result(value: "Error checking alerts: \(error.localizedDescription)")
        }
    }
}

// MARK: - Open Dashboards Intent

struct OpenDashboardsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open GrafLens Dashboards"
    static var description = IntentDescription("Open the GrafLens dashboards view")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct GrafLensShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckAlertsIntent(),
            phrases: [
                "Check \(.applicationName) alerts",
                "Are there any \(.applicationName) alerts",
                "Check Grafana alerts with \(.applicationName)",
            ],
            shortTitle: "Check Alerts",
            systemImageName: "bell.badge"
        )

        AppShortcut(
            intent: OpenDashboardsIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName) dashboards",
            ],
            shortTitle: "Open Dashboards",
            systemImageName: "square.grid.2x2"
        )
    }
}
