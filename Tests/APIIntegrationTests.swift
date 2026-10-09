import Foundation

@main struct APIIntegrationTests {
    static func main() async throws {
        let client = GrafanaAPIClient(connection: ServerConnection(url: "http://127.0.0.1:18764", useServiceAccount: false))
        let dashboard = try await client.getDashboard(uid: "preview").dashboard
        precondition(dashboard.allowsNativeRendering)
        let panel = dashboard.allPanels.first { $0.id == 4 }!
        let short = try await client.queryNativePanel(panel, from: "now-5m")
        let long = try await client.queryNativePanel(panel, from: "now-6h")
        precondition(short.series.count == 2 && long.series.count == 2)
        precondition(abs(short.to.timeIntervalSince(short.from) - 300) < 0.01)
        precondition(abs(long.to.timeIntervalSince(long.from) - 21600) < 0.01)
        precondition(abs(short.series[0].samples.first!.timestamp.timeIntervalSince(short.from)) < 0.01)
        precondition(abs(long.series[0].samples.first!.timestamp.timeIntervalSince(long.from)) < 0.01)
        let annotations = try await client.queryNativePanel(panel, from: "now-6h", annotationDashboardUID: "preview")
        precondition(annotations.annotations.count == 2)
        precondition(annotations.annotations.contains { $0.timeEnd != nil })
        let gapPanel = dashboard.allPanels.first { $0.id == 6 }!
        let gap = try await client.queryNativePanel(gapPanel, from: "now-1h")
        precondition(gap.series[0].segments.count == 2)
        var unsupported = panel.document
        unsupported["targets"] = .array([.object(["refId": .string("A"), "expr": .string("temperature{$host}"), "datasource": .object(["uid": .string("prom"), "type": .string("prometheus")])])])
        do { _ = try await client.queryNativePanel(Panel(document: unsupported), from: "now-1h"); fatalError("Templated queries need Grafana") }
        catch NativePanelError.unsupported { }
        let light = await client.panelEmbedURL(dashboardUID: "preview", panelID: 7, from: "now-5m", theme: "light")!
        let dark = await client.panelEmbedURL(dashboardUID: "preview", panelID: 7, from: "now-6h", theme: "dark")!
        precondition(light != dark)
        let components = URLComponents(url: dark, resolvingAgainstBaseURL: false)!
        precondition(components.queryItems!.contains(URLQueryItem(name: "from", value: "now-6h")))
        precondition(components.queryItems!.contains(URLQueryItem(name: "theme", value: "dark")))
        print("Passed native API integration: range changes, multi-series decoding, data gaps, unsupported-query fallback, and embed URL parameters.")
    }
}
