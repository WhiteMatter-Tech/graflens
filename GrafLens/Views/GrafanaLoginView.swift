import SwiftUI
import WebKit

struct GrafanaLoginView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var webAuthManager: WebAuthManager
    @Environment(\.dismiss) var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Retry") {
                            self.error = nil
                        }
                        .font(.caption.bold())
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                }

                GrafanaLoginWebView(
                    baseURL: connectionManager.activeConnection?.baseURL,
                    webAuthManager: webAuthManager,
                    onAuthenticated: {
                        webAuthManager.markAuthenticated()
                        dismiss()
                    },
                    onError: { err in
                        self.error = err
                    }
                )
            }
            .navigationTitle("Sign In to Grafana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct GrafanaLoginWebView: UIViewRepresentable {
    let baseURL: URL?
    let webAuthManager: WebAuthManager
    let onAuthenticated: () -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = webAuthManager.makeWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        if let url = baseURL {
            webView.load(URLRequest(url: url.appendingPathComponent("/login")))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, onAuthenticated: onAuthenticated, onError: onError)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let baseURL: URL?
        let onAuthenticated: () -> Void
        let onError: (String) -> Void

        init(baseURL: URL?, onAuthenticated: @escaping () -> Void, onError: @escaping (String) -> Void) {
            self.baseURL = baseURL
            self.onAuthenticated = onAuthenticated
            self.onError = onError
        }

        // MARK: - Navigation Policy

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""

            // Allow http/https normally
            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
                return
            }

            // Handle custom schemes by opening in system browser
            if scheme != "about" && scheme != "blob" && scheme != "data" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - Navigation Completed

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            let path = url.path

            // After OIDC login, Grafana redirects back to "/" or a dashboard URL
            if !path.hasPrefix("/login") && !path.contains("/auth/") && !path.contains("/oauth/") {
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    let hasSession = cookies.contains { cookie in
                        cookie.name == "grafana_session" ||
                        cookie.name == "grafana_session_expiry" ||
                        cookie.name.hasPrefix("grafana")
                    }
                    if hasSession {
                        DispatchQueue.main.async {
                            self.onAuthenticated()
                        }
                    }
                }
            }
        }

        // MARK: - Error Handling

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            // Ignore cancellation errors (from navigation policy cancels)
            if nsError.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                self.onError(error.localizedDescription)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                self.onError(error.localizedDescription)
            }
        }

        // MARK: - UI Delegate (handle popups/new windows from OIDC)

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // OIDC providers sometimes open popups — load them in the same webview instead
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
