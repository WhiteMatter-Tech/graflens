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

            // Preload panels for all dashboards so the widget panel picker
            // can show every panel without the user opening each dashboard.
            Task.detached {
                await Self.preloadPanelsForWidget(dashboards: results, client: client)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private static func preloadPanelsForWidget(dashboards: [DashboardSearchResult], client: GrafanaAPIClient) async {
        await withTaskGroup(of: Void.self) { group in
            // Cap concurrency: only 5 in-flight at once to avoid hammering the server.
            var inFlight = 0
            for dash in dashboards {
                // Skip dashboards whose cached panels already include query info.
                let cached = SharedDataManager.loadCachedPanels(dashboardUID: dash.uid)
                if !cached.isEmpty && cached.contains(where: { $0.targets != nil && !($0.targets!.isEmpty) }) {
                    continue
                }
                if inFlight >= 5 {
                    await group.next()
                    inFlight -= 1
                }
                inFlight += 1
                group.addTask {
                    guard let response = try? await client.getDashboard(uid: dash.uid) else { return }
                    let panelInfos = response.dashboard.allPanels
                        .filter { $0.isVisualization }
                        .map { DashboardDetailViewModel.panelInfoFrom($0) }
                    if !panelInfos.isEmpty {
                        SharedDataManager.cachePanelList(dashboardUID: dash.uid, panels: panelInfos)
                    }
                }
            }
        }
    }
}
