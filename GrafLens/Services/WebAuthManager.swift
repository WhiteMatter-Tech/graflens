import Foundation
import WebKit

@MainActor
class WebAuthManager: ObservableObject {
    @Published var isAuthenticated = false

    let dataStore: WKWebsiteDataStore

    private let authCheckKey = "webAuthCompleted"

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
