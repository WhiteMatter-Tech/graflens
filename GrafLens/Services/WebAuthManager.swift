import Foundation
import WebKit

@MainActor
class WebAuthManager: ObservableObject {
    @Published var isAuthenticated = false

    let dataStore: WKWebsiteDataStore

    @Published var sessionRevision = 0
    private var authCheckKey = "webAuthCompleted-unscoped"

    func selectConnection(_ id: UUID?) {
        authCheckKey = "webAuthCompleted-" + (id?.uuidString ?? "none")
        isAuthenticated = UserDefaults.standard.bool(forKey: authCheckKey)
        sessionRevision += 1
    }

    init() {
        self.dataStore = WKWebsiteDataStore.default()
        self.isAuthenticated = UserDefaults.standard.bool(forKey: authCheckKey)
    }

    func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        return config
    }

    func markAuthenticated() {
        sessionRevision += 1
        isAuthenticated = true
        UserDefaults.standard.set(true, forKey: authCheckKey)
    }

    func clearSession() {
        isAuthenticated = false
        UserDefaults.standard.set(false, forKey: authCheckKey)
        dataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                self.dataStore.httpCookieStore.delete(cookie)
            }
        }
    }
}
