import Foundation
import SwiftUI

@MainActor
class FavoritesManager: ObservableObject {
    @Published var favoriteUIDs: Set<String> = []
    @Published var recentDashboards: [RecentDashboard] = []

    private var favoritesKey = "favoriteDashboardUIDs-unscoped"
    private var recentsKey = "recentDashboards-unscoped"
    private let maxRecents = 15

    func selectConnection(_ id: UUID?) {
        let defaults = UserDefaults.standard
        favoritesKey = "favoriteDashboardUIDs-" + (id?.uuidString ?? "none")
        recentsKey = "recentDashboards-" + (id?.uuidString ?? "none")
        // Legacy favorites belonged to the connection active at upgrade time.
        if id != nil && !defaults.bool(forKey: "favoritesV2Migrated") {
            if defaults.object(forKey: favoritesKey) == nil {
                defaults.set(defaults.object(forKey: "favoriteDashboardUIDs"), forKey: favoritesKey)
                defaults.set(defaults.object(forKey: "recentDashboards"), forKey: recentsKey)
            }
            defaults.set(true, forKey: "favoritesV2Migrated")
        }
        favoriteUIDs = []; recentDashboards = []
        loadFavorites(); loadRecents()
    }

    // MARK: - Favorites

    func isFavorite(_ uid: String) -> Bool {
        favoriteUIDs.contains(uid)
    }

    func toggleFavorite(_ uid: String) {
        if favoriteUIDs.contains(uid) {
            favoriteUIDs.remove(uid)
        } else {
            favoriteUIDs.insert(uid)
        }
        saveFavorites()
    }

    // MARK: - Recents

    func recordVisit(uid: String, title: String, folderTitle: String?) {
        let recent = RecentDashboard(uid: uid, title: title, folderTitle: folderTitle, visitedAt: Date())
        recentDashboards.removeAll { $0.uid == uid }
        recentDashboards.insert(recent, at: 0)
        if recentDashboards.count > maxRecents {
            recentDashboards = Array(recentDashboards.prefix(maxRecents))
        }
        saveRecents()
    }

    // MARK: - Persistence

    private func saveFavorites() {
        let array = Array(favoriteUIDs)
        UserDefaults.standard.set(array, forKey: favoritesKey)
    }

    private func loadFavorites() {
        let array = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        favoriteUIDs = Set(array)
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentDashboards) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let saved = try? JSONDecoder().decode([RecentDashboard].self, from: data) else { return }
        recentDashboards = saved
    }
}

struct RecentDashboard: Codable, Identifiable {
    let uid: String
    let title: String
    let folderTitle: String?
    let visitedAt: Date

    var id: String { uid }
}
