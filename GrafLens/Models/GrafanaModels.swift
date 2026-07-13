import Foundation

// MARK: - Health Check

struct GrafanaHealth: Codable {
    let commit: String?
    let database: String?
    let version: String?
}

// MARK: - Dashboard Search Result

struct DashboardSearchResult: Codable, Identifiable, Hashable {
    let id: Int
    let uid: String
    let title: String
    let uri: String?
    let url: String?
    let type: String?
    let tags: [String]?
    let isStarred: Bool?
    let folderUid: String?
    let folderTitle: String?
    let folderUrl: String?

    var displayFolderTitle: String {
        folderTitle ?? "General"
    }
}

// MARK: - Dashboard Detail

struct DashboardResponse: Codable {
    let dashboard: DashboardDetail
    let meta: DashboardMeta?
}

struct DashboardMeta: Codable {
    let slug: String?
    let url: String?
    let folderTitle: String?
    let folderUid: String?
    let created: String?
    let updated: String?
    let createdBy: String?
    let updatedBy: String?
}

struct DashboardDetail: Codable {
    let id: Int?
    let uid: String?
    let title: String?
    let description: String?
    let tags: [String]?
    let panels: [Panel]?
    let rows: [Row]?
    let time: TimeRange?
    let refresh: RefreshValue?
    let templating: Templating?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        uid = try container.decodeIfPresent(String.self, forKey: .uid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        panels = try container.decodeIfPresent([Panel].self, forKey: .panels)
        rows = try container.decodeIfPresent([Row].self, forKey: .rows)
        time = try container.decodeIfPresent(TimeRange.self, forKey: .time)
        refresh = try container.decodeIfPresent(RefreshValue.self, forKey: .refresh)
        // Never let a malformed template variable fail the whole dashboard:
        // decode templating leniently and drop to nil on any error.
        templating = (try? container.decodeIfPresent(Templating.self, forKey: .templating)) ?? nil
    }

    var allPanels: [Panel] {
        var result: [Panel] = []
        if let panels = panels {
            for panel in panels {
                if panel.type == "row" {
                    if let nested = panel.panels {
                        result.append(contentsOf: nested)
                    }
                } else {
                    result.append(panel)
                }
            }
        }
        if let rows = rows {
            for row in rows {
                if let rowPanels = row.panels {
                    result.append(contentsOf: rowPanels)
                }
            }
        }
        return result
    }
}

enum RefreshValue: Codable {
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .bool(let b): try container.encode(b)
        }
    }
}

struct TimeRange: Codable {
    let from: String?
    let to: String?
}

struct Row: Codable {
    let title: String?
    let panels: [Panel]?
}

struct Panel: Codable, Identifiable {
    let id: Int
    let title: String?
    let type: String?
    let description: String?
    let gridPos: GridPos?
    let panels: [Panel]?
    let targets: [Target]?
    let datasource: FlexibleDatasource?

    var displayTitle: String {
        let t = title ?? ""
        return t.isEmpty ? "Panel \(id)" : t
    }

    var isVisualization: Bool {
        guard let type = type else { return false }
        let nonVisual = ["row", "text"]
        return !nonVisual.contains(type)
    }
}

struct GridPos: Codable {
    let h: Int?
    let w: Int?
    let x: Int?
    let y: Int?
}

/// Grafana datasource references can be a string (name) or an object (uid+type).
enum FlexibleDatasource: Codable {
    case name(String)
    case reference(uid: String?, type: String?)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .name(str)
        } else {
            let obj = try container.decode(DatasourceRef.self)
            self = .reference(uid: obj.uid, type: obj.type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .name(let n): try container.encode(n)
        case .reference(let uid, let type):
            try container.encode(DatasourceRef(uid: uid, type: type))
        }
    }

    var uid: String? {
        switch self {
        case .name: return nil
        case .reference(let uid, _): return uid
        }
    }

    var type: String? {
        switch self {
        case .name: return nil
        case .reference(_, let type): return type
        }
    }

    var nameValue: String? {
        switch self {
        case .name(let n): return n
        case .reference: return nil
        }
    }

    private struct DatasourceRef: Codable {
        let uid: String?
        let type: String?
    }
}

struct Target: Codable {
    let refId: String?
    let expr: String?
    let rawSql: String?
    let datasource: FlexibleDatasource?
}

// MARK: - Template Variables

struct Templating: Codable {
    let list: [TemplateVariable]?
}

/// A dashboard template variable (`dashboard.templating.list[]`).
struct TemplateVariable: Codable, Identifiable {
    let name: String
    let label: String?
    let type: String?
    let hide: Int?
    let query: TemplateQuery?
    let current: TemplateSelection?
    let options: [TemplateOption]?
    let multi: Bool?
    let includeAll: Bool?
    let allValue: String?
    let datasource: FlexibleDatasource?

    var id: String { name }

    var displayLabel: String {
        if let label = label, !label.isEmpty { return label }
        return name
    }

    /// 0 = show label + control, 1 = show control only, 2 = do not render.
    var hideMode: Int { hide ?? 0 }

    var isMultiValue: Bool { multi ?? false }

    /// Types that Phase 1 can resolve and edit purely from dashboard JSON.
    /// `query` (needs datasource resolution), `datasource`, and multi-value
    /// variables are rendered read-only until later phases.
    var isEditable: Bool {
        guard !isMultiValue else { return false }
        switch type {
        case "custom", "interval", "textbox": return true
        default: return false
        }
    }

    /// The selectable options for a custom/interval variable, preferring the
    /// baked `options[]` and falling back to parsing the `query` string.
    var resolvedOptions: [TemplateOption] {
        if let options = options, !options.isEmpty {
            return options.filter { $0.rawValue != "$__all" }
        }
        guard let raw = query?.stringValue, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map { part -> TemplateOption in
            let piece = part.trimmingCharacters(in: .whitespaces)
            // Custom variables may be written as "Display : value".
            if let range = piece.range(of: " : ") {
                let text = String(piece[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(piece[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return TemplateOption(text: .single(text), value: .single(value), selected: nil)
            }
            return TemplateOption(text: .single(piece), value: .single(piece), selected: nil)
        }
    }

    /// The variable's current value(s) from the dashboard JSON, used to seed
    /// selection state before the user changes anything.
    var defaultValues: [String] {
        if let values = current?.value?.values, !values.isEmpty { return values }
        if let constant = query?.stringValue, type == "constant" { return [constant] }
        return []
    }
}

/// A template variable's `query`, which is a string for custom/constant/
/// textbox/interval/datasource variables and an object for query variables.
enum TemplateQuery: Codable {
    case string(String)
    case object

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            self = .object
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .object: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

struct TemplateSelection: Codable {
    let text: TemplateValue?
    let value: TemplateValue?
}

struct TemplateOption: Codable, Hashable {
    let text: TemplateValue?
    let value: TemplateValue?
    let selected: Bool?

    var displayText: String { text?.display ?? value?.display ?? "" }
    var rawValue: String { value?.display ?? text?.display ?? "" }
}

/// A template value that Grafana serializes as either a single string or, for
/// multi-value variables, an array of strings.
enum TemplateValue: Codable, Hashable {
    case single(String)
    case multiple([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .single(str)
        } else if let arr = try? container.decode([String].self) {
            self = .multiple(arr)
        } else {
            self = .single("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let s): try container.encode(s)
        case .multiple(let a): try container.encode(a)
        }
    }

    var values: [String] {
        switch self {
        case .single(let s): return s.isEmpty ? [] : [s]
        case .multiple(let a): return a
        }
    }

    var display: String {
        switch self {
        case .single(let s): return s
        case .multiple(let a): return a.joined(separator: " + ")
        }
    }
}

// MARK: - Folder

struct GrafanaFolder: Codable, Identifiable {
    let id: Int
    let uid: String
    let title: String
}

// MARK: - Organization

struct GrafanaOrg: Codable, Identifiable {
    let id: Int
    let name: String
}

// MARK: - Data Source

struct DataSource: Codable, Identifiable {
    let id: Int
    let uid: String?
    let name: String
    let type: String
    let url: String?
    let isDefault: Bool?
}

// MARK: - Annotations

struct GrafanaAnnotation: Codable, Identifiable {
    let id: Int
    let dashboardId: Int?
    let dashboardUID: String?
    let panelId: Int?
    let time: Int64
    let timeEnd: Int64?
    let text: String
    let tags: [String]?
    let login: String?
    let email: String?
    let avatarUrl: String?
    let created: Int64?
    let updated: Int64?
}

struct AnnotationCreateRequest: Codable {
    let dashboardUID: String?
    let panelId: Int?
    let time: Int64
    let timeEnd: Int64?
    let text: String
    let tags: [String]?
}

struct AnnotationResponse: Codable {
    let id: Int?
    let message: String?
}

// MARK: - Alert Rules

struct AlertRuleGroupResponse: Codable {
    let data: AlertRuleGroupData?
    let status: String?
}

struct AlertRuleGroupData: Codable {
    let groups: [AlertRuleGroup]?
}

struct AlertRuleGroup: Codable, Identifiable {
    let name: String?
    let file: String?
    let rules: [AlertRule]?

    var id: String { name ?? UUID().uuidString }
}

struct AlertRule: Codable, Identifiable {
    let name: String?
    let query: String?
    let state: String?
    let health: String?
    let type: String?
    let labels: [String: String]?
    let annotations: [String: String]?
    let alerts: [GrafanaAlertInstance]?

    var id: String { name ?? UUID().uuidString }
    var displayName: String { name ?? "Unknown Rule" }
    var severity: String { labels?["severity"] ?? "unknown" }
}

struct GrafanaAlertInstance: Codable, Identifiable {
    let labels: [String: String]?
    let annotations: [String: String]?
    let state: String?
    let activeAt: String?
    let value: String?

    var id: String {
        (labels ?? [:]).sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    var alertName: String { labels?["alertname"] ?? "Unknown" }
    var severity: String { labels?["severity"] ?? "unknown" }
}

// MARK: - Alert Silences

struct AlertSilence: Codable, Identifiable {
    let id: String
    let status: SilenceStatus?
    let comment: String?
    let createdBy: String?
    let startsAt: String?
    let endsAt: String?
    let matchers: [SilenceMatcher]?
}

struct SilenceStatus: Codable {
    let state: String?
}

struct SilenceMatcher: Codable {
    let name: String
    let value: String
    let isRegex: Bool
    let isEqual: Bool?
}

struct SilenceCreateRequest: Codable {
    let matchers: [SilenceMatcher]
    let startsAt: String
    let endsAt: String
    let createdBy: String
    let comment: String
}

struct SilenceResponse: Codable {
    let silenceID: String?
}

// MARK: - Dashboard Save

struct DashboardSaveRequest: Codable {
    let dashboard: DashboardSavePayload
    let folderUid: String?
    let message: String?
    let overwrite: Bool
}

struct DashboardSavePayload: Codable {
    let id: Int?
    let uid: String?
    let title: String?
    let description: String?
    let tags: [String]?
    let panels: [Panel]?
    let time: TimeRange?
    let refresh: RefreshValue?
    let version: Int?
}

struct DashboardSaveResponse: Codable {
    let id: Int?
    let uid: String?
    let url: String?
    let status: String?
    let version: Int?
}

// MARK: - Snapshots

struct SnapshotCreateRequest: Codable {
    let dashboard: DashboardSavePayload
    let expires: Int?
}

struct SnapshotResponse: Codable {
    let deleteKey: String?
    let deleteUrl: String?
    let key: String?
    let url: String?
    let id: Int?
}

struct SnapshotListItem: Codable, Identifiable {
    let id: Int
    let name: String?
    let key: String?
    let externalUrl: String?
    let expires: String?
    let created: String?
}

// MARK: - Playlists

struct GrafanaPlaylist: Codable, Identifiable {
    let id: Int?
    let uid: String?
    let name: String?
    let interval: String?
    let items: [PlaylistItem]?

    var displayName: String { name ?? "Playlist \(id ?? 0)" }
}

struct PlaylistItem: Codable {
    let type: String?
    let value: String?
    let title: String?
}

struct PlaylistCreateRequest: Codable {
    let name: String
    let interval: String
    let items: [PlaylistItem]
}

// MARK: - Folder CRUD

struct FolderCreateRequest: Codable {
    let title: String
    let uid: String?
}

// MARK: - Star / Tags

struct MessageResponse: Codable {
    let message: String?
}

struct DashboardTagCount: Codable {
    let term: String
    let count: Int
}

// MARK: - Synthetic Monitoring

/// A Synthetic Monitoring check, as returned by the SM datasource proxy
/// (`/sm/check/list`). The check type is inferred from which key is present
/// in `settings` (http, ping, dns, tcp, traceroute, ...).
struct SyntheticCheck: Codable, Identifiable {
    let id: Int
    let job: String
    let target: String
    let enabled: Bool
    let frequency: Int?
    let probes: [Int]?
    let labels: [SyntheticLabel]?
    let settings: SyntheticSettings

    var displayName: String { job.isEmpty ? target : job }

    var checkType: String { settings.type }

    var probeCount: Int { probes?.count ?? 0 }

    /// Key used to join a check against its Prometheus series, which carry
    /// `job` and `instance` (= target) labels.
    var metricKey: String { SyntheticCheck.metricKey(job: job, instance: target) }

    static func metricKey(job: String, instance: String) -> String {
        "\(job)\u{1}\(instance)"
    }

    var frequencyDescription: String? {
        guard let ms = frequency else { return nil }
        let seconds = ms / 1000
        if seconds >= 60 && seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    var typeDisplayName: String {
        switch checkType {
        case "http": return "HTTP"
        case "ping": return "Ping"
        case "dns": return "DNS"
        case "tcp": return "TCP"
        case "traceroute": return "Traceroute"
        case "grpc": return "gRPC"
        case "multihttp": return "MultiHTTP"
        case "scripted", "k6": return "Scripted"
        case "browser": return "Browser"
        default: return checkType.capitalized
        }
    }

    var typeSymbolName: String {
        switch checkType {
        case "http", "multihttp": return "globe"
        case "ping": return "wave.3.right"
        case "dns": return "signpost.right"
        case "tcp", "grpc": return "network"
        case "traceroute": return "point.topleft.down.to.point.bottomright.curvepath"
        case "scripted", "k6", "browser": return "curlybraces"
        default: return "checkmark.shield"
        }
    }
}

struct SyntheticLabel: Codable, Hashable {
    let name: String
    let value: String
}

/// Decodes only the check type from the `settings` object by finding which
/// known check-type key is present.
struct SyntheticSettings: Codable {
    let type: String

    private static let knownTypes = [
        "http", "ping", "dns", "tcp", "traceroute", "grpc",
        "multihttp", "scripted", "k6", "browser"
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        for candidate in SyntheticSettings.knownTypes {
            if let key = DynamicCodingKey(stringValue: candidate), container.contains(key) {
                type = candidate
                return
            }
        }
        type = container.allKeys.first?.stringValue ?? "unknown"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        if let key = DynamicCodingKey(stringValue: type) {
            try container.encodeNil(forKey: key)
        }
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// One labeled sample returned from an instant Prometheus query.
struct SyntheticMetricSample {
    let labels: [String: String]
    let value: Double
}

/// Live status/uptime/latency for a single check, derived from Prometheus.
struct SyntheticCheckStats {
    var up: Bool?
    var uptimePercent: Double?
    var avgDurationSeconds: Double?
}

/// Subset of `/api/frontend/settings` used to discover datasources without
/// the admin-only `/api/datasources` endpoint (available to any user).
struct FrontendSettings: Codable {
    let datasources: [String: FrontendDatasource]?
}

struct FrontendDatasource: Codable {
    let type: String?
    let uid: String?
    let name: String?
}

// MARK: - Server Connection

struct ServerConnection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var apiKey: String
    var useServiceAccount: Bool

    init(id: UUID = UUID(), name: String = "", url: String = "https://play.grafana.org", apiKey: String = "", useServiceAccount: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.useServiceAccount = useServiceAccount
    }

    var displayName: String {
        name.isEmpty ? url : name
    }

    var baseURL: URL? {
        var urlString = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        // Strip any path/query/fragment so users can paste any Grafana URL
        // (e.g. https://play.grafana.org/dashboards → https://play.grafana.org)
        guard let parsed = URLComponents(string: urlString) else { return nil }
        var components = URLComponents()
        components.scheme = parsed.scheme
        components.host = parsed.host
        components.port = parsed.port
        return components.url
    }
}
