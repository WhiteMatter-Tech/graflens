import SwiftUI
import WebKit

/// Owned by a dashboard (or its expanded sheet), rather than its recycled cards.
/// Keeps one current result and live web page per panel; released with the screen.
@MainActor final class PanelSessionCache: ObservableObject {
    private var panels: [Int: PanelPresentationModel] = [:]

    func model(for panelID: Int) -> PanelPresentationModel {
        if let model = panels[panelID] { return model }
        let model = PanelPresentationModel()
        panels[panelID] = model
        return model
    }

    func retainPanels(_ ids: [Int]) {
        let retained = Set(ids)
        panels = panels.filter { retained.contains($0.key) }
    }
}

struct PanelLoadRequest: Equatable {
    let connectionID: UUID?
    let dashboardUID: String
    let panel: [String: JSONValue]
    let from: String
    let theme: String
    var variables: [String: [String]] = [:]
    let native: Bool
    let annotations: Bool
    let refreshID: Int
    let localRefresh: Int
    let sessionRevision: Int
}

@MainActor final class PanelPresentationModel: ObservableObject {
    @Published var result: NativePanelResult?
    @Published var configuration: NativePanelConfiguration?
    @Published var webURL: URL?
    @Published var error: String?
    @Published var fallbackReason: String?
    @Published var forceGrafana = false
    @Published var localRefresh = 0
    let webState = PanelWebState()
    private(set) var requestID = UUID()
    private var request: PanelLoadRequest?
    private var loadTask: Task<Void, Never>?

    deinit { loadTask?.cancel() }

    func load(_ request: PanelLoadRequest, client: GrafanaAPIClient?) {
        // Reappearance and simultaneous appearances share the same in-flight work.
        guard self.request != request else { return }
        self.request = request
        loadTask?.cancel()
        requestID = UUID()
        result = nil; configuration = nil; webURL = nil; error = nil; fallbackReason = nil
        webState.invalidate()
        guard let client else { error = "Connect to a server to view this panel."; return }
        let generation = requestID
        // This task belongs to the session, so scrolling away cannot cancel it.
        // Don't retain the model across the fetch: closing the screen cancels work.
        loadTask = Task { [weak self] in
            let response = await Self.fetch(request, client: client)
            guard !Task.isCancelled, let self, generation == self.requestID else { return }
            self.configuration = response.configuration
            self.result = response.result
            self.webURL = response.webURL
            self.error = response.error
            self.fallbackReason = response.fallbackReason
            self.loadTask = nil
        }
    }

    private struct Response {
        var result: NativePanelResult?
        var configuration: NativePanelConfiguration?
        var webURL: URL?
        var error: String?
        var fallbackReason: String?
    }

    private static func fetch(_ request: PanelLoadRequest, client: GrafanaAPIClient) async -> Response {
        let panel = Panel(document: request.panel)
        var response = Response()
        if request.native, let config = NativePanelConfiguration.supported(panel) {
            do {
                response.result = try await client.queryNativePanel(panel, from: request.from,
                    annotationDashboardUID: request.annotations ? request.dashboardUID : nil)
                response.configuration = config
                return response
            } catch {
                guard !Task.isCancelled else { return response }
                response.fallbackReason = error.localizedDescription
            }
        } else {
            response.fallbackReason = "Grafana rendering preserves this panel's queries, transformations, annotations, and display settings."
        }
        response.webURL = await client.panelEmbedURL(dashboardUID: request.dashboardUID, panelID: panel.id,
            from: request.from, theme: request.theme, variables: request.variables)
        if response.webURL == nil { response.error = "This server's panel URL is invalid." }
        return response
    }
}

@MainActor final class PanelWebState: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var isLoading = true
    @Published var error: String?
    @Published var loadedAt: Date?
    private(set) var webView: WKWebView?
    private var requestID: UUID?
    private var navigation: WKNavigation?
    private var pendingRequest: (url: URL, id: UUID)?
    private var currentURL: URL?
    private var recoveryCount = 0
    private var readinessTask: Task<Void, Never>?
    private let renderTimeout: TimeInterval

    init(renderTimeout: TimeInterval = 30) {
        self.renderTimeout = renderTimeout
        super.init()
    }

    deinit { readinessTask?.cancel() }

    func makeWebView(auth: WebAuthManager) -> WKWebView {
        if let webView { return webView }
        let webView = WKWebView(frame: .zero, configuration: auth.makeWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        // The dashboard already handles safe areas. Embedded pages need the
        // whole card viewport, including when the card sits beneath a toolbar.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    func load(_ url: URL, requestID: UUID) {
        guard self.requestID != requestID else { return }
        pendingRequest = (url, requestID)
        viewportDidLayout()
    }

    func viewportDidLayout() {
        // SwiftUI first creates representables with zero bounds. Starting Grafana
        // there can leave its client-side panel layout empty even after didFinish.
        Task { @MainActor [weak self] in self?.startPendingRequest() }
    }

    private func startPendingRequest() {
        guard let webView, webView.window != nil, let host = webView.superview,
              host.bounds.size == webView.bounds.size,
              webView.bounds.width > 1, webView.bounds.height > 1,
              let pending = pendingRequest else { return }
        pendingRequest = nil
        guard requestID != pending.id else { return }
        readinessTask?.cancel()
        requestID = pending.id
        currentURL = pending.url
        recoveryCount = 0
        reset()
        navigation = webView.load(URLRequest(url: pending.url))
    }

    func didReattach() {
        viewportDidLayout()
        guard loadedAt != nil, !isLoading else { return }
        // Repaint a retained page after reattachment without refetching it.
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('resize'))", completionHandler: nil)
    }

    func invalidate() {
        readinessTask?.cancel()
        readinessTask = nil
        pendingRequest = nil
        currentURL = nil
        recoveryCount = 0
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        requestID = nil
        navigation = nil
        reset()
    }

    private func reset() { isLoading = true; error = nil; loadedAt = nil }

    func snapshot() async throws -> UIImage {
        guard let webView, !isLoading, error == nil else { throw GrafanaAPIError.invalidResponse }
        return try await webView.takeSnapshot(configuration: nil)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        reset()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, navigation === self.navigation else { return }
        if webView.url?.path.contains("/login") == true {
            isLoading = false
            error = "Sign in to Grafana from the dashboard menu, then refresh this panel."
            loadedAt = nil
            return
        }
        checkForRenderedContent(webView, navigation: navigation)
    }

    private func checkForRenderedContent(_ webView: WKWebView, navigation: WKNavigation?) {
        readinessTask?.cancel()
        let deadline = Date().addingTimeInterval(renderTimeout)
        readinessTask = Task { @MainActor [weak self, weak webView] in
            while !Task.isCancelled {
                guard let webView else { return }
                let painted = (try? await webView.evaluateJavaScript(Self.visibleContentProbe)) as? Bool ?? false
                guard !Task.isCancelled else { return }
                if self?.acceptRenderProbe(painted, navigation: navigation, deadline: deadline) != false { return }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    private func acceptRenderProbe(_ painted: Bool, navigation: WKNavigation?, deadline: Date) -> Bool {
        guard navigation === self.navigation, error == nil else { return true }
        if painted {
            isLoading = false
            loadedAt = Date()
            readinessTask = nil
            return true
        }
        if Date() >= deadline {
            recoverBlankPage("Grafana didn't draw this panel. Try again or expand it.")
            return true
        }
        return false
    }

    private func recoverBlankPage(_ message: String) {
        readinessTask?.cancel()
        readinessTask = nil
        guard recoveryCount < 1, let webView, let currentURL else {
            isLoading = false; error = message; loadedAt = nil
            return
        }
        // One recovery per explicit request. Scrolling never resets this budget.
        recoveryCount += 1
        reset()
        navigation = webView.load(URLRequest(url: currentURL))
    }

    private static let visibleContentProbe = #"""
    (() => {
        if (!document.body || innerWidth < 2 || innerHeight < 2) return false;
        const candidates = [document.body, ...document.body.querySelectorAll('*')];
        for (const el of candidates) {
            const r = el.getBoundingClientRect();
            if (r.width < 2 || r.height < 2 || r.bottom <= 0 || r.right <= 0 || r.top >= innerHeight || r.left >= innerWidth) continue;
            const style = getComputedStyle(el);
            if (style.display === 'none' || style.visibility !== 'visible' || Number(style.opacity) === 0) continue;
            if (el.closest('script,style,template,#splash-screen,.preloader')) continue;
            if (el.matches('canvas,svg,img,input')) return true;
            if (Array.from(el.childNodes).some(n => n.nodeType === Node.TEXT_NODE && n.textContent.trim())) return true;
        }
        return false;
    })()
    """#

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(navigation, error: error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(navigation, error: error) }
    private func fail(_ navigation: WKNavigation?, error: Error) {
        guard navigation === self.navigation, (error as NSError).code != NSURLErrorCancelled else { return }
        readinessTask?.cancel()
        isLoading = false
        if self.error == nil { self.error = error.localizedDescription }
        loadedAt = nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard webView === self.webView else { decisionHandler(.cancel); return }
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            isLoading = false; loadedAt = nil
            error = response.statusCode == 401 || response.statusCode == 403
                ? "Sign in to Grafana from the dashboard menu, then refresh this panel."
                : "Grafana returned an error (\(response.statusCode)). Try refreshing the panel."
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        recoverBlankPage("The panel stopped responding. Try again or expand it.")
    }
}

/// A separate UIKit host prevents SwiftUI from resizing or detaching the cached
/// WKWebView through an obsolete representable when cards move between rows.
@MainActor final class PanelWebContainer: UIView {
    private let state: PanelWebState
    private let page: WKWebView

    init(state: PanelWebState, auth: WebAuthManager) {
        self.state = state
        self.page = state.makeWebView(auth: auth)
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(page)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard page.superview === self, bounds.width > 1, bounds.height > 1 else { return }
        page.frame = bounds
        state.viewportDidLayout()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            setNeedsLayout()
            state.didReattach()
        }
    }
    func detach() {
        // A replacement host might already own this page. Never detach it there.
        if page.superview === self { page.removeFromSuperview() }
    }
}

struct GrafanaPanelWebView: UIViewRepresentable {
    let url: URL
    let requestID: UUID
    let webAuthManager: WebAuthManager
    @ObservedObject var state: PanelWebState

    func makeUIView(context: Context) -> PanelWebContainer { PanelWebContainer(state: state, auth: webAuthManager) }
    func updateUIView(_ container: PanelWebContainer, context: Context) {
        state.load(url, requestID: requestID)
        container.setNeedsLayout()
    }
    func makeCoordinator() -> PanelWebState { state }
    static func dismantleUIView(_ container: PanelWebContainer, coordinator: PanelWebState) {
        // Retain the page and navigation in the session while detaching its host.
        container.detach()
    }
}
