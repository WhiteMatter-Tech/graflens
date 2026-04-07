import Foundation
import SwiftUI

@MainActor
class AlertsViewModel: ObservableObject {
    @Published var firingAlerts: [GrafanaAlertInstance] = []
    @Published var ruleGroups: [AlertRuleGroup] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedAlertForSilence: GrafanaAlertInstance?

    func load(client: GrafanaAPIClient?) async {
        guard let client = client else { return }
        isLoading = true
        error = nil

        do {
            async let alertsTask = client.getFiringAlerts()
            async let rulesTask = client.getAlertRules()

            let alerts = try await alertsTask
            let rulesResponse = try await rulesTask

            firingAlerts = alerts.filter { $0.state?.lowercased() == "firing" }
            ruleGroups = rulesResponse.data?.groups ?? []
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
