import Foundation

enum GrafanaAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .invalidResponse: return "Invalid response from server"
        case .unauthorized: return "Unauthorized - check your API key"
        case .forbidden: return "Access forbidden - insufficient permissions"
        case .notFound: return "Resource not found"
        case .serverError(let code): return "Server error (\(code))"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError(let error): return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

actor GrafanaAPIClient {
    private let connection: ServerConnection
    private let session: URLSession

    init(connection: ServerConnection) {
        self.connection = connection
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Health

    func checkHealth() async throws -> GrafanaHealth {
        return try await request(path: "/api/health")
    }

    // MARK: - Dashboards

    func searchDashboards(query: String? = nil, tag: String? = nil, folderUid: String? = nil) async throws -> [DashboardSearchResult] {
        var params: [(String, String)] = [("type", "dash-db"), ("limit", "1000")]
        if let query = query, !query.isEmpty {
            params.append(("query", query))
        }
        if let tag = tag, !tag.isEmpty {
            params.append(("tag", tag))
        }
        if let folderUid = folderUid {
            params.append(("folderUids", folderUid))
        }
        return try await request(path: "/api/search", queryItems: params)
    }

    func getDashboard(uid: String) async throws -> DashboardResponse {
        return try await request(path: "/api/dashboards/uid/\(uid)")
    }

    // MARK: - Folders

    func getFolders() async throws -> [GrafanaFolder] {
        return try await request(path: "/api/folders", queryItems: [("limit", "1000")])
    }

    // MARK: - Data Sources

    func getDataSources() async throws -> [DataSource] {
        return try await request(path: "/api/datasources")
    }

    // MARK: - Orgs

    func getCurrentOrg() async throws -> GrafanaOrg {
        return try await request(path: "/api/org")
    }

    // MARK: - Star / Unstar

    func starDashboard(id: Int) async throws -> MessageResponse {
        return try await postRequest(path: "/api/user/stars/dashboard/\(id)", body: Optional<String>.none)
    }

    func unstarDashboard(id: Int) async throws -> MessageResponse {
        return try await deleteRequest(path: "/api/user/stars/dashboard/\(id)")
    }

    // MARK: - Tags

    func getDashboardTags() async throws -> [DashboardTagCount] {
        return try await request(path: "/api/dashboards/tags")
    }

    // MARK: - Annotations

    func getAnnotations(dashboardUID: String? = nil, from: Int64? = nil, to: Int64? = nil, limit: Int = 100) async throws -> [GrafanaAnnotation] {
        var params: [(String, String)] = [("limit", "\(limit)")]
        if let uid = dashboardUID { params.append(("dashboardUID", uid)) }
        if let from = from { params.append(("from", "\(from)")) }
        if let to = to { params.append(("to", "\(to)")) }
        return try await request(path: "/api/annotations", queryItems: params)
    }

    func createAnnotation(_ annotation: AnnotationCreateRequest) async throws -> AnnotationResponse {
        return try await postRequest(path: "/api/annotations", body: annotation)
    }

    func deleteAnnotation(id: Int) async throws -> MessageResponse {
        return try await deleteRequest(path: "/api/annotations/\(id)")
    }

    // MARK: - Alert Rules

    func getAlertRules() async throws -> AlertRuleGroupResponse {
        return try await request(path: "/api/prometheus/grafana/api/v1/rules")
    }

    // MARK: - Firing Alerts

    func getFiringAlerts() async throws -> [GrafanaAlertInstance] {
        struct AlertsWrapper: Codable {
            let data: AlertsWrapperData?
            let status: String?
        }
        struct AlertsWrapperData: Codable {
            let alerts: [GrafanaAlertInstance]?
        }
        let response: AlertsWrapper = try await request(path: "/api/prometheus/grafana/api/v1/alerts")
        return response.data?.alerts ?? []
    }

    // MARK: - Silences

    func getSilences() async throws -> [AlertSilence] {
        return try await request(path: "/api/alertmanager/grafana/api/v2/silences")
    }

    func createSilence(_ silence: SilenceCreateRequest) async throws -> SilenceResponse {
        return try await postRequest(path: "/api/alertmanager/grafana/api/v2/silences", body: silence)
    }

    func deleteSilence(id: String) async throws -> MessageResponse {
        return try await deleteRequest(path: "/api/alertmanager/grafana/api/v2/silence/\(id)")
    }

    // MARK: - Dashboard Save

    func saveDashboard(_ request: DashboardSaveRequest) async throws -> DashboardSaveResponse {
        return try await postRequest(path: "/api/dashboards/db", body: request)
    }

    // MARK: - Snapshots

    func getSnapshots() async throws -> [SnapshotListItem] {
        return try await request(path: "/api/dashboard/snapshots")
    }

    func createSnapshot(_ snapshot: SnapshotCreateRequest) async throws -> SnapshotResponse {
        return try await postRequest(path: "/api/snapshots", body: snapshot)
    }

    func deleteSnapshot(key: String) async throws -> MessageResponse {
        return try await deleteRequest(path: "/api/snapshots/\(key)")
    }

    // MARK: - Folders CRUD

    func createFolder(_ folder: FolderCreateRequest) async throws -> GrafanaFolder {
        return try await postRequest(path: "/api/folders", body: folder)
    }

    func deleteFolder(uid: String) async throws -> MessageResponse {
        return try await deleteRequest(path: "/api/folders/\(uid)")
    }

    // MARK: - Playlists

    func getPlaylists() async throws -> [GrafanaPlaylist] {
        return try await request(path: "/api/playlists")
    }

    func createPlaylist(_ playlist: PlaylistCreateRequest) async throws -> GrafanaPlaylist {
        return try await postRequest(path: "/api/playlists", body: playlist)
    }

    func deletePlaylist(uid: String) async throws -> MessageResponse {
        return try await deleteRequest(path: "/api/playlists/\(uid)")
    }

    // MARK: - Panel Embed URL

    func panelEmbedURL(dashboardUID: String, panelID: Int, from: String = "now-6h", to: String = "now", theme: String = "dark") -> URL? {
        guard let base = connection.baseURL else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/d-solo/\(dashboardUID)"
        components?.queryItems = [
            URLQueryItem(name: "orgId", value: "1"),
            URLQueryItem(name: "panelId", value: "\(panelID)"),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "theme", value: theme),
        ]
        return components?.url
    }

    func dashboardURL(uid: String) -> URL? {
        guard let base = connection.baseURL else { return nil }
        return base.appendingPathComponent("/d/\(uid)")
    }

    var authHeaderValue: String {
        "Bearer \(connection.apiKey)"
    }

    var baseURL: URL? {
        connection.baseURL
    }

    // MARK: - Private

    private func postRequest<T: Decodable, B: Encodable>(path: String, body: B?) async throws -> T {
        guard let baseURL = connection.baseURL else { throw GrafanaAPIError.invalidURL }
        let url = baseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        if !connection.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(connection.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }
        return try await executeRequest(urlRequest)
    }

    private func deleteRequest<T: Decodable>(path: String) async throws -> T {
        guard let baseURL = connection.baseURL else { throw GrafanaAPIError.invalidURL }
        let url = baseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        if !connection.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(connection.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await executeRequest(urlRequest)
    }

    private func executeRequest<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GrafanaAPIError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrafanaAPIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300: break
        case 401: throw GrafanaAPIError.unauthorized
        case 403: throw GrafanaAPIError.forbidden
        case 404: throw GrafanaAPIError.notFound
        default: throw GrafanaAPIError.serverError(httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GrafanaAPIError.decodingError(error)
        }
    }

    private func request<T: Decodable>(path: String, queryItems: [(String, String)] = []) async throws -> T {
        guard let baseURL = connection.baseURL else {
            throw GrafanaAPIError.invalidURL
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        guard let url = components?.url else {
            throw GrafanaAPIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        if !connection.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(connection.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GrafanaAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrafanaAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw GrafanaAPIError.unauthorized
        case 403:
            throw GrafanaAPIError.forbidden
        case 404:
            throw GrafanaAPIError.notFound
        default:
            throw GrafanaAPIError.serverError(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GrafanaAPIError.decodingError(error)
        }
    }
}
