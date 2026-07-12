import Foundation
import SwiftUI

@MainActor
class DashboardDetailViewModel: ObservableObject {
    @Published var dashboard: DashboardDetail?
    @Published var meta: DashboardMeta?
    @Published var panels: [Panel] = []
    @Published var isLoading = false
    @Published var error: String?

    /// Template variables to render in the bar (excludes `hide == 2`).
    @Published var variables: [TemplateVariable] = []
    /// Current selection per variable name.
    @Published var selections: [String: [String]] = [:]

    let dashboardUID: String
    let dashboardTitle: String

    init(uid: String, title: String) {
        self.dashboardUID = uid
        self.dashboardTitle = title
    }

    /// `var-<name>=<value>` map passed to panel embed URLs. Includes hidden
    /// variables (e.g. constants) so panels still receive their values.
    var variableParams: [String: [String]] {
        var params: [String: [String]] = [:]
        for variable in allVariables {
            let values = selections[variable.name] ?? variable.defaultValues
            if !values.isEmpty { params[variable.name] = values }
        }
        return params
    }

    /// All variables including hidden ones, used for value resolution.
    private var allVariables: [TemplateVariable] {
        dashboard?.templating?.list ?? []
    }

    func updateSelection(_ variable: TemplateVariable, values: [String]) {
        selections[variable.name] = values
        persistSelections()
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
            loadVariables(response.dashboard.templating?.list ?? [])

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

    // MARK: - Template Variables

    private func loadVariables(_ list: [TemplateVariable]) {
        // Only variables with a control get rendered; hidden ones (hide == 2)
        // still contribute values via `variableParams`.
        variables = list.filter { $0.hideMode != 2 }

        let persisted = Self.loadPersistedSelections(uid: dashboardUID)
        var initial: [String: [String]] = [:]
        for variable in list {
            if let saved = persisted[variable.name], !saved.isEmpty {
                initial[variable.name] = saved
            } else {
                initial[variable.name] = variable.defaultValues
            }
        }
        selections = initial
    }

    private func persistSelections() {
        var store = Self.loadStore()
        store[dashboardUID] = selections
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    private static let storeKey = "dashboardVariableSelections"

    private static func loadStore() -> [String: [String: [String]]] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let store = try? JSONDecoder().decode([String: [String: [String]]].self, from: data) else {
            return [:]
        }
        return store
    }

    private static func loadPersistedSelections(uid: String) -> [String: [String]] {
        loadStore()[uid] ?? [:]
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
