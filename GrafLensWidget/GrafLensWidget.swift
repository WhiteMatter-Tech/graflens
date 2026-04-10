import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct PanelWidgetEntry: TimelineEntry {
    let date: Date
    let dashboardTitle: String
    let panelTitle: String
    let panelImageData: Data?
    let connectionName: String?
    let isPlaceholder: Bool

    static var placeholder: PanelWidgetEntry {
        PanelWidgetEntry(
            date: Date(),
            dashboardTitle: "Dashboard",
            panelTitle: "Panel",
            panelImageData: nil,
            connectionName: "Grafana",
            isPlaceholder: true
        )
    }

    static var unconfigured: PanelWidgetEntry {
        PanelWidgetEntry(
            date: Date(),
            dashboardTitle: "",
            panelTitle: "Tap to configure",
            panelImageData: nil,
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
        return identifiers.map { uid in
            if let dash = dashboards.first(where: { $0.uid == uid }) {
                return DashboardEntity(id: dash.uid, title: dash.title)
            }
            return DashboardEntity(id: uid, title: uid)
        }
    }

    func suggestedEntities() async throws -> [DashboardEntity] {
        if let connection = SharedDataManager.loadActiveConnection() {
            let client = GrafanaAPIClient(connection: connection)
            if let results = try? await client.searchDashboards() {
                SharedDataManager.cacheDashboardList(results)
                return results.map { DashboardEntity(id: $0.uid, title: $0.title) }
            }
        }
        let cached = SharedDataManager.loadCachedDashboards()
        return cached.map { DashboardEntity(id: $0.uid, title: $0.title) }
    }
}

struct PanelEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Panel")
    static var defaultQuery = PanelEntityQuery()

    var id: String
    var title: String
    var dashboardUID: String
    var panelID: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct PanelEntityQuery: EntityQuery {
    static let separator = "::"

    @IntentParameterDependency<SelectPanelIntent>(
        \.$dashboard
    )
    var dashboardDependency

    func entities(for identifiers: [String]) async throws -> [PanelEntity] {
        var results: [PanelEntity] = []
        for identifier in identifiers {
            guard let range = identifier.range(of: Self.separator, options: .backwards) else { continue }
            let dashUID = String(identifier[..<range.lowerBound])
            guard let panelID = Int(identifier[range.upperBound...]) else { continue }
            let panels = SharedDataManager.loadCachedPanels(dashboardUID: dashUID)
            let title = panels.first(where: { $0.id == panelID })?.title ?? "Panel \(panelID)"
            results.append(PanelEntity(id: identifier, title: title, dashboardUID: dashUID, panelID: panelID))
        }
        return results
    }

    func suggestedEntities() async throws -> [PanelEntity] {
        if let dashboard = dashboardDependency?.dashboard {
            let panels = SharedDataManager.loadCachedPanels(dashboardUID: dashboard.id)
            return panels.map { panel in
                PanelEntity(
                    id: "\(dashboard.id)\(Self.separator)\(panel.id)",
                    title: panel.title,
                    dashboardUID: dashboard.id,
                    panelID: panel.id
                )
            }
        }
        return []
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
        await buildEntry(for: configuration, family: context.family)
    }

    func timeline(for configuration: SelectPanelIntent, in context: Context) async -> Timeline<PanelWidgetEntry> {
        let entry = await buildEntry(for: configuration, family: context.family)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func buildEntry(for configuration: SelectPanelIntent, family: WidgetFamily) async -> PanelWidgetEntry {
        guard let connection = SharedDataManager.loadActiveConnection() else {
            return .unconfigured
        }

        guard let panel = configuration.panel,
              let dashboard = configuration.dashboard else {
            return .unconfigured
        }

        // Load the panel snapshot cached by the main app's WKWebView.
        // Falls back to Grafana's server-side render API if no snapshot exists.
        var imageData = SharedDataManager.loadPanelSnapshot(
            dashboardUID: panel.dashboardUID,
            panelID: panel.panelID
        )

        if imageData == nil {
            let timeRange = configuration.timeRange ?? "6h"
            let from = "now-\(timeRange)"
            let (width, height): (Int, Int) = {
                switch family {
                case .systemSmall:  return (400, 400)
                case .systemMedium: return (800, 400)
                case .systemLarge:  return (800, 800)
                default:            return (800, 400)
                }
            }()
            imageData = await Self.fetchPanelImage(
                connection: connection,
                dashboardUID: panel.dashboardUID,
                panelID: panel.panelID,
                width: width, height: height,
                from: from, to: "now"
            )
        }

        return PanelWidgetEntry(
            date: Date(),
            dashboardTitle: dashboard.title,
            panelTitle: panel.title,
            panelImageData: imageData,
            connectionName: connection.displayName,
            isPlaceholder: false
        )
    }

    /// Fetches a PNG snapshot from Grafana's /render endpoint (requires grafana-image-renderer plugin).
    private static func fetchPanelImage(
        connection: ServerConnection,
        dashboardUID: String,
        panelID: Int,
        width: Int, height: Int,
        from: String, to: String
    ) async -> Data? {
        guard let baseURL = connection.baseURL else { return nil }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/render/d-solo/\(dashboardUID)"
        components?.queryItems = [
            URLQueryItem(name: "orgId", value: "1"),
            URLQueryItem(name: "panelId", value: "\(panelID)"),
            URLQueryItem(name: "width", value: "\(width)"),
            URLQueryItem(name: "height", value: "\(height)"),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "theme", value: "dark"),
        ]

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if !connection.apiKey.isEmpty {
            request.setValue("Bearer \(connection.apiKey)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let contentType = http.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("image") else {
            return nil
        }

        return data
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
        Group {
            if let imageData = entry.panelImageData,
               let uiImage = UIImage(data: imageData) {
                // Full-bleed panel image — looks exactly like Grafana.
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // No snapshot yet — user needs to open the dashboard in the app first.
                VStack(spacing: 6) {
                    Text(entry.panelTitle)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: family == .systemSmall ? 32 : 44))
                        .foregroundStyle(.orange)

                    Text(entry.dashboardTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("Open this dashboard in the app to capture a snapshot")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            }
        }
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
