import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct PanelWidgetEntry: TimelineEntry {
    let date: Date
    let dashboardTitle: String
    let panelTitle: String
    let panelType: String?
    let embedURL: URL?
    let connectionName: String?
    let isPlaceholder: Bool

    static var placeholder: PanelWidgetEntry {
        PanelWidgetEntry(
            date: Date(),
            dashboardTitle: "Dashboard",
            panelTitle: "Panel",
            panelType: "graph",
            embedURL: nil,
            connectionName: "Grafana",
            isPlaceholder: true
        )
    }

    static var unconfigured: PanelWidgetEntry {
        PanelWidgetEntry(
            date: Date(),
            dashboardTitle: "",
            panelTitle: "Tap to configure",
            panelType: nil,
            embedURL: nil,
            connectionName: nil,
            isPlaceholder: false
        )
    }
}

// MARK: - App Intent Configuration

struct DashboardEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dashboard")
    static var defaultQuery = DashboardEntityQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct DashboardEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DashboardEntity] {
        let dashboards = SharedDataManager.loadCachedDashboards()
        return identifiers.compactMap { uid in
            guard let dash = dashboards.first(where: { $0.uid == uid }) else { return nil }
            return DashboardEntity(id: dash.uid, title: dash.title)
        }
    }

    func suggestedEntities() async throws -> [DashboardEntity] {
        let dashboards = SharedDataManager.loadCachedDashboards()
        return dashboards.map { DashboardEntity(id: $0.uid, title: $0.title) }
    }
}

struct PanelEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Panel")
    static var defaultQuery = PanelEntityQuery()

    var id: String // "dashboardUID_panelID"
    var title: String
    var dashboardUID: String
    var panelID: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct PanelEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PanelEntity] {
        var results: [PanelEntity] = []
        for identifier in identifiers {
            let parts = identifier.split(separator: "_", maxSplits: 1)
            guard parts.count == 2, let panelID = Int(parts[1]) else { continue }
            let dashUID = String(parts[0])
            let panels = SharedDataManager.loadCachedPanels(dashboardUID: dashUID)
            if let panel = panels.first(where: { $0.id == panelID }) {
                results.append(PanelEntity(id: identifier, title: panel.title, dashboardUID: dashUID, panelID: panelID))
            }
        }
        return results
    }

    func suggestedEntities() async throws -> [PanelEntity] {
        let dashboards = SharedDataManager.loadCachedDashboards()
        var results: [PanelEntity] = []
        for dash in dashboards.prefix(10) {
            let panels = SharedDataManager.loadCachedPanels(dashboardUID: dash.uid)
            for panel in panels {
                results.append(PanelEntity(
                    id: "\(dash.uid)_\(panel.id)",
                    title: "\(dash.title) — \(panel.title)",
                    dashboardUID: dash.uid,
                    panelID: panel.id
                ))
            }
        }
        return results
    }
}

struct SelectPanelIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Panel"
    static var description = IntentDescription("Choose a Grafana panel to display")

    @Parameter(title: "Dashboard")
    var dashboard: DashboardEntity?

    @Parameter(title: "Panel")
    var panel: PanelEntity?

    @Parameter(title: "Time Range", default: "6h")
    var timeRange: String?
}

// MARK: - Timeline Provider

struct PanelWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = PanelWidgetEntry
    typealias Intent = SelectPanelIntent

    func placeholder(in context: Context) -> PanelWidgetEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectPanelIntent, in context: Context) async -> PanelWidgetEntry {
        await buildEntry(for: configuration)
    }

    func timeline(for configuration: SelectPanelIntent, in context: Context) async -> Timeline<PanelWidgetEntry> {
        let entry = await buildEntry(for: configuration)
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func buildEntry(for configuration: SelectPanelIntent) async -> PanelWidgetEntry {
        guard let connection = SharedDataManager.loadActiveConnection() else {
            return .unconfigured
        }

        guard let panel = configuration.panel,
              let dashboard = configuration.dashboard else {
            return .unconfigured
        }

        let timeRange = configuration.timeRange ?? "6h"
        let from = "now-\(timeRange)"
        let client = GrafanaAPIClient(connection: connection)
        let embedURL = await client.panelEmbedURL(
            dashboardUID: panel.dashboardUID,
            panelID: panel.panelID,
            from: from,
            to: "now",
            theme: "dark"
        )

        return PanelWidgetEntry(
            date: Date(),
            dashboardTitle: dashboard.title,
            panelTitle: panel.title,
            panelType: nil,
            embedURL: embedURL,
            connectionName: connection.displayName,
            isPlaceholder: false
        )
    }
}

// MARK: - Widget Views

struct PanelWidgetView: View {
    var entry: PanelWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.isPlaceholder {
            placeholderView
        } else if entry.connectionName == nil {
            unconfiguredView
        } else {
            configuredView
        }
    }

    private var configuredView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.xaxis.ascending")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(entry.panelTitle)
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()
                Text(timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Panel visual placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.08))

                VStack(spacing: 4) {
                    Image(systemName: panelIcon)
                        .font(family == .systemSmall ? .title3 : .title2)
                        .foregroundStyle(.orange)

                    if family != .systemSmall {
                        Text(entry.dashboardTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Footer
            if family != .systemSmall {
                HStack {
                    Image(systemName: "server.rack")
                        .font(.caption2)
                    Text(entry.connectionName ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var unconfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Tap to configure")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Select a Grafana panel")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 80, height: 12)
                Spacer()
            }
            Spacer()
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.15))
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 60, height: 10)
                Spacer()
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var panelIcon: String {
        switch entry.panelType?.lowercased() {
        case "gauge": return "gauge.medium"
        case "stat": return "number"
        case "barchart": return "chart.bar"
        case "table": return "tablecells"
        case "piechart": return "chart.pie"
        case "logs": return "doc.text"
        default: return "chart.xyaxis.line"
        }
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(entry.date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h"
    }
}

// MARK: - Widget Definition

struct GrafLensPanelWidget: Widget {
    let kind = "GrafLensPanelWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectPanelIntent.self,
            provider: PanelWidgetProvider()
        ) { entry in
            PanelWidgetView(entry: entry)
        }
        .configurationDisplayName("Grafana Panel")
        .description("Display a Grafana dashboard panel on your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct GrafLensWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrafLensPanelWidget()
    }
}
