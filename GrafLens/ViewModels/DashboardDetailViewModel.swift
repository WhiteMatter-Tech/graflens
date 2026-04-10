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
                Self.panelInfoFrom($0)
            }
            SharedDataManager.cachePanelList(dashboardUID: dashboardUID, panels: panelInfos)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    nonisolated static func panelInfoFrom(_ panel: Panel) -> PanelInfo {
        let dsUID = panel.targets?.first?.datasource?.uid ?? panel.datasource?.uid
        let dsType = panel.targets?.first?.datasource?.type ?? panel.datasource?.type
        let targets = panel.targets?.compactMap { t -> PanelInfoTarget? in
            guard t.expr != nil || t.rawSql != nil else { return nil }
            return PanelInfoTarget(refId: t.refId ?? "A", expr: t.expr, rawSql: t.rawSql)
        }
        return PanelInfo(
            id: panel.id,
            title: panel.displayTitle,
            type: panel.type,
            datasourceUID: dsUID,
            datasourceType: dsType,
            targets: targets
        )
    }
}
