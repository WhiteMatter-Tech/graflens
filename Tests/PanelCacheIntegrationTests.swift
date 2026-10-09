import SwiftUI
import WebKit

/// Simulator-only integration harness. Compiles the production cache and renderer.
@main @MainActor final class PanelCacheIntegrationTests: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var checks = 0
    private let base = "http://127.0.0.1:18765"
    private var log = ""

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Tests", sessionRole: session.role)
        configuration.delegateClass = CacheTestSceneDelegate.self
        return configuration
    }

    func start(in window: UIWindow) {
        self.window = window
        Task {
            do {
                try await run()
                report("PASS: \(checks) panel cache integration checks")
            } catch { report("FAIL: \(error)") }
        }
    }

    private struct Failure: Error { let message: String }
    private func check(_ value: Bool, _ message: String) throws {
        guard value else { throw Failure(message: message) }
        checks += 1
        log += "PASS: \(message)\n"
    }
    private func report(_ result: String) {
        log += result + "\n"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("results.txt")
        try? log.write(to: path, atomically: true, encoding: .utf8)
        print(log)
    }
    private func wait(_ message: String, until predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure(message: "Timed out: \(message)")
    }
    private func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/cache-counts")!)
        return try JSONDecoder().decode([String: Int].self, from: data)
    }
    private func mount(_ state: PanelWebState, auth: WebAuthManager, url: URL, id: UUID) {
        window?.rootViewController = UIHostingController(rootView:
            GrafanaPanelWebView(url: url, requestID: id, webAuthManager: auth, state: state).id(id))
    }
    private func unmount() { window?.rootViewController = UIViewController() }

    private func run() async throws {
        let connection = ServerConnection(url: base, useServiceAccount: false)
        let client = GrafanaAPIClient(connection: connection)
        let panel = try await client.getDashboard(uid: "preview").dashboard.allPanels.first { $0.id == 4 }!
        func request(from: String = "now-6h", theme: String = "light", refresh: Int = 0,
                     local: Int = 0, auth: Int = 0, connectionID: UUID? = nil,
                     document: [String: JSONValue]? = nil, native: Bool = true,
                     annotations: Bool = false) -> PanelLoadRequest {
            PanelLoadRequest(connectionID: connectionID ?? connection.id, dashboardUID: "preview",
                panel: document ?? panel.document, from: from, theme: theme, native: native,
                annotations: annotations, refreshID: refresh, localRefresh: local, sessionRevision: auth)
        }
        var cache: PanelSessionCache? = PanelSessionCache()
        weak var releasedModel: PanelPresentationModel?
        do {
            let model = cache!.model(for: panel.id)
            releasedModel = model
            let first = request()
            let appearance = Task { model.load(first, client: client) }
            await appearance.value
            appearance.cancel()
            for _ in 0..<20 { cache!.model(for: panel.id).load(first, client: client) }
            try await wait("native load") { model.result != nil }
            try check(try await counts()["queries"] == 1, "Reappearances coalesce in-flight native requests, even after the view task is cancelled")
            let loadedAt = model.result!.loadedAt
            for _ in 0..<20 { cache!.model(for: panel.id).load(first, client: client) }
            try check(model.result?.loadedAt == loadedAt, "A completed native result survives repeated appearances")
            try check(cache!.model(for: panel.id) === model, "Recreated cards receive the same session")
            model.forceGrafana = true; model.localRefresh = 3
            try check(cache!.model(for: panel.id).forceGrafana && cache!.model(for: panel.id).localRefresh == 3,
                "Renderer preference and panel refresh revision survive recycling")

            var changed = panel.document
            changed["title"] = .string("Changed configuration")
            let changes = [request(from: "now-5m"), request(theme: "dark"), request(refresh: 1),
                request(local: 1), request(auth: 1), request(connectionID: UUID()),
                request(document: changed), request(annotations: true)]
            for (index, next) in changes.enumerated() {
                model.load(next, client: client)
                try await wait("invalidated native request") { model.result != nil }
                try check(try await counts()["queries"] == index + 2, "Request change \(index + 1) performs exactly one fresh query")
            }
            model.load(request(native: false), client: client)
            try await wait("renderer switch") { model.webURL != nil }
            try check(model.result == nil, "Switching to Grafana invalidates the native result")
            model.load(request(from: "now-30d"), client: client)
            try await Task.sleep(for: .milliseconds(100))
            model.load(request(from: "now-5m"), client: client)
            try await wait("superseding request") { model.result != nil }
            try await Task.sleep(for: .milliseconds(400))
            try check(abs(model.result!.to.timeIntervalSince(model.result!.from) - 300) < 1,
                "A superseded slow request cannot overwrite the selected range")
            cache!.retainPanels([panel.id])
            try check(cache!.model(for: panel.id) === model, "Dashboard refresh retains surviving panel sessions")
        }
        cache = nil
        try check(releasedModel == nil, "Closing a dashboard releases its native session")

        var pending: PanelSessionCache? = PanelSessionCache()
        weak let pendingModel = pending!.model(for: panel.id)
        pendingModel!.load(request(), client: client)
        try await Task.sleep(for: .milliseconds(80))
        pending = nil
        try check(pendingModel == nil, "In-flight work does not retain a closed dashboard")

        let auth = WebAuthManager()
        var webCache: PanelSessionCache? = PanelSessionCache()
        weak var releasedWebView: WKWebView?
        do {
            let state = webCache!.model(for: 7).webState
            let url = URL(string: base + "/cache-page")!
            let id = UUID()
            mount(state, auth: auth, url: url, id: id)
            try await wait("first web page") { state.loadedAt != nil }
            let webView = state.webView!
            releasedWebView = webView
            let loadedAt = state.loadedAt
            _ = try await webView.evaluateJavaScript("document.getElementById('value').value = 'kept'; window.panelMarker = 42")
            unmount()
            try await Task.sleep(for: .milliseconds(200))
            mount(state, auth: auth, url: url, id: id)
            try await Task.sleep(for: .milliseconds(500))
            try check(state.webView === webView, "Reattaching a card reuses the actual WKWebView")
            try check(try await counts()["pages"] == 1, "Reattaching a loaded web card makes no extra page request")
            try check(state.loadedAt == loadedAt, "Reattaching preserves the original page load time")
            let marker = try await webView.evaluateJavaScript("window.panelMarker") as? Int
            let input = try await webView.evaluateJavaScript("document.getElementById('value').value") as? String
            try check(marker == 42 && input == "kept", "Interactive page state survives detachment")

            unmount()
            state.invalidate()
            let nextID = UUID()
            mount(state, auth: auth, url: url, id: nextID)
            try await wait("second page starts") { state.webView?.isLoading == true }
            unmount()
            try await wait("offscreen page completes") { state.loadedAt != nil }
            mount(state, auth: auth, url: url, id: nextID)
            try await Task.sleep(for: .milliseconds(500))
            try check(try await counts()["pages"] == 2, "A web navigation finishes offscreen without restarting on return")
            try check(state.webView !== webView, "Invalidation replaces stale web content")
            unmount()
            state.invalidate()
            mount(state, auth: auth, url: URL(string: base + "/cache-page?theme=dark")!, id: UUID())
            try await wait("refreshed web page") { state.loadedAt != nil }
            try check(try await counts()["pages"] == 3, "An explicit web refresh makes exactly one new page request")
            releasedWebView = state.webView
            unmount()
        }
        webCache = nil
        try await wait("web view released") { releasedWebView == nil }
        try check(releasedWebView == nil, "Disposed dashboard pages are released")
        try await renderingChecks(auth: auth)
    }

    private func renderingChecks(auth: WebAuthManager) async throws {
        let delayed = PanelWebState()
        mount(delayed, auth: auth, url: URL(string: base + "/render-delayed")!, id: UUID())
        try await wait("delayed page navigation") { delayed.webView?.url != nil && delayed.webView?.isLoading == false }
        try check(delayed.isLoading && delayed.loadedAt == nil, "Navigation completion does not mark an empty page ready")
        try await wait("delayed content appears") { delayed.loadedAt != nil }
        try check(!delayed.isLoading && delayed.error == nil, "Asynchronous text and code content completes readiness")
        unmount()
        delayed.invalidate()

        let recovered = PanelWebState(renderTimeout: 0.6)
        let recoveryURL = URL(string: base + "/render-recover")!
        let recoveryID = UUID()
        mount(recovered, auth: auth, url: recoveryURL, id: recoveryID)
        try await wait("blank page recovers") { recovered.loadedAt != nil }
        try check(try await counts()["recover"] == 2, "An empty page gets one automatic recovery")
        unmount()
        mount(recovered, auth: auth, url: recoveryURL, id: recoveryID)
        try await Task.sleep(for: .milliseconds(700))
        try check(try await counts()["recover"] == 2, "Reattaching a recovered page does not reload it")
        // Exercise the delegate path without deliberately crashing a WebKit process.
        recovered.webViewWebContentProcessDidTerminate(recovered.webView!)
        try check(recovered.error != nil && recovered.loadedAt == nil, "Process recovery shares the same bounded retry budget")
        unmount()
        recovered.invalidate()

        let blank = PanelWebState(renderTimeout: 0.6)
        let blankURL = URL(string: base + "/render-blank")!
        let blankID = UUID()
        mount(blank, auth: auth, url: blankURL, id: blankID)
        try await wait("persistent blank error") { blank.error != nil }
        let blankRequests = try await counts()["blank"]
        try check(!blank.isLoading && blank.loadedAt == nil && blankRequests == 2,
            "A persistent blank page shows an error after exactly one retry")
        unmount()
        mount(blank, auth: auth, url: blankURL, id: blankID)
        try await Task.sleep(for: .milliseconds(700))
        try check(try await counts()["blank"] == 2, "Scrolling cannot restart a failed page's recovery budget")
        unmount()
        blank.invalidate()

        let layout = PanelWebState()
        let controller = UIViewController()
        window?.rootViewController = controller
        let oldHost = PanelWebContainer(state: layout, auth: auth)
        controller.view.addSubview(oldHost)
        let layoutID = UUID()
        layout.load(URL(string: base + "/render-layout")!, requestID: layoutID)
        try await Task.sleep(for: .milliseconds(400))
        try check(try await counts()["layout"] == nil, "A zero-sized host does not start navigation")
        oldHost.frame = CGRect(x: 0, y: 0, width: 320, height: 250)
        oldHost.layoutIfNeeded()
        try await wait("sized page") { layout.loadedAt != nil }
        let dimensions = try await layout.webView!.evaluateJavaScript("document.body.textContent") as? String
        try check(dimensions == "320 x 250", "The first page script sees the final panel dimensions (actual: \(dimensions ?? "nil"), bounds: \(layout.webView!.bounds))")
        let newHost = PanelWebContainer(state: layout, auth: auth)
        newHost.frame = oldHost.frame
        controller.view.addSubview(newHost)
        newHost.layoutIfNeeded()
        oldHost.detach()
        oldHost.removeFromSuperview()
        try check(layout.webView?.superview === newHost, "Disposing an obsolete host cannot detach the replacement's page")
        layout.load(URL(string: base + "/render-layout")!, requestID: layoutID)
        try await Task.sleep(for: .milliseconds(400))
        try check(try await counts()["layout"] == 1, "Moving between hosts preserves the cached navigation")
        layout.webViewWebContentProcessDidTerminate(layout.webView!)
        try await wait("process recovery") { layout.loadedAt != nil }
        try check(try await counts()["layout"] == 2, "A terminated content process gets one recovery")
        unmount()
        layout.invalidate()
    }
}

@MainActor final class CacheTestSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        (UIApplication.shared.delegate as? PanelCacheIntegrationTests)?.start(in: window)
    }
}
