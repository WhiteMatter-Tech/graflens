import Foundation
import SwiftUI

@MainActor
class DashboardDetailViewModel: ObservableObject {
    @Published var dashboard: DashboardDetail?
    @Published var meta: DashboardMeta?
    @Published var panels: [Panel] = []
    @Published var isLoading = false
    @Published var error: String?

    let dashboardUID: String
    let dashboardTitle: String

    init(uid: String, title: String) {
        self.dashboardUID = uid
        self.dashboardTitle = title
    }

    func loadDashboard(client: GrafanaAPIClient?) async {
        guard let client = client else { return }
        isLoading = true
        error = nil

        do {
            let response = try await client.getDashboard(uid: dashboardUID)
            dashboard = response.dashboard
            meta = response.meta
            panels = response.dashboard.allPanels

            // Cache panels for widget configuration
            let panelInfos = panels.filter { $0.isVisualization }.map {
                PanelInfo(id: $0.id, title: $0.displayTitle, type: $0.type)
            }
            SharedDataManager.cachePanelList(dashboardUID: dashboardUID, panels: panelInfos)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
