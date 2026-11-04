import Foundation

@main struct AuthErrorIntegrationTests {
    static func main() async throws {
        func client(_ path: String) -> GrafanaAPIClient {
            GrafanaAPIClient(connection: ServerConnection(url: "http://127.0.0.1:18768", apiKey: "fixture-" + path))
        }
        let health = try await client("ok").checkHealth()
        precondition(health.version == "13.0.0")
        do {
            _ = try await client("reject").checkHealth()
            fatalError("Expected a 401")
        } catch GrafanaAPIError.unauthorized { }
        do {
            _ = try await client("redirect").checkHealth()
            fatalError("Expected a browser login redirect")
        } catch GrafanaAPIError.webSignInRequired { }
        do {
            _ = try await client("deny").starDashboard(id: 1)
            fatalError("Expected a 403 on POST")
        } catch GrafanaAPIError.forbidden { }
        do {
            _ = try await client("html").unstarDashboard(id: 1)
            fatalError("Expected HTML detection on DELETE")
        } catch GrafanaAPIError.webPageReturned { }
        print("Passed 5 HTTP integration checks: valid JSON, rejected authentication, followed login redirect, POST denial, and DELETE HTML response.")
    }
}
