import Foundation
import SwiftUI

@MainActor
class DashboardListViewModel: ObservableObject {
    @Published var dashboards: [DashboardSearchResult] = []
    @Published var folders: [String: [DashboardSearchResult]] = [:]
    @Published var folderOrder: [String] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var searchText = ""

    private var allDashboards: [DashboardSearchResult] = []

    var filteredFolderOrder: [String] {
        if searchText.isEmpty { return folderOrder }
        return folderOrder.filter { folder in
            filteredDashboards(in: folder).count > 0
        }
    }

    func filteredDashboards(in folder: String) -> [DashboardSearchResult] {
        guard let items = folders[folder] else { return [] }
        if searchText.isEmpty { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.title.lowercased().contains(query) ||
            ($0.tags ?? []).contains(where: { $0.lowercased().contains(query) })
        }
    }

    func loadDashboards(client: GrafanaAPIClient?) async {
        guard let client = client else { return }
        isLoading = true
        error = nil

        do {
            let results = try await client.searchDashboards()
            allDashboards = results

            var grouped: [String: [DashboardSearchResult]] = [:]
            for dash in results {
                let folder = dash.displayFolderTitle
                grouped[folder, default: []].append(dash)
            }

            for key in grouped.keys {
                grouped[key]?.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }

            folders = grouped
            folderOrder = grouped.keys.sorted { a, b in
                if a == "General" { return true }
                if b == "General" { return false }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            dashboards = results

            // Cache for widget configuration
            SharedDataManager.cacheDashboardList(results)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
