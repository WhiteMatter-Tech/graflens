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
