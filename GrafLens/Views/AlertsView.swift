import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @StateObject private var viewModel = AlertsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.firingAlerts.isEmpty {
                    ProgressView("Loading alerts...")
                } else if let error = viewModel.error {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await viewModel.load(client: connectionManager.apiClient) } }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                } else if viewModel.firingAlerts.isEmpty && viewModel.ruleGroups.isEmpty {
                    ContentUnavailableView {
                        Label("No Alerts", systemImage: "bell.slash")
                    } description: {
                        Text("No alert rules or firing alerts found.")
                    }
                } else {
                    alertList
                }
            }
            .navigationTitle("Alerts")
            .refreshable { await viewModel.load(client: connectionManager.apiClient) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SilencesView()) {
                        Image(systemName: "bell.slash")
                    }
                }
            }
            .sheet(item: $viewModel.selectedAlertForSilence) { alert in
                CreateSilenceView(alertInstance: alert)
            }
        }
        .task { await viewModel.load(client: connectionManager.apiClient) }
    }

    private var alertList: some View {
        List {
            if !viewModel.firingAlerts.isEmpty {
                Section("Firing") {
                    ForEach(viewModel.firingAlerts) { alert in
                        AlertInstanceRow(alert: alert) {
                            viewModel.selectedAlertForSilence = alert
                        }
                    }
                }
            }

            ForEach(viewModel.ruleGroups) { group in
                Section(group.name ?? "Rules") {
                    ForEach(group.rules ?? []) { rule in
                        AlertRuleRow(rule: rule)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Alert Instance Row

struct AlertInstanceRow: View {
    let alert: GrafanaAlertInstance
    let onSilence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(alert.alertName)
                    .font(.body.bold())
                    .lineLimit(1)
                Spacer()
                Text(alert.severity)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityColor.opacity(0.15))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())
            }

            if let desc = alert.annotations?["description"] ?? alert.annotations?["summary"] {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let activeAt = alert.activeAt {
                Text("Active since \(activeAt)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button {
                HapticManager.medium()
                onSilence()
            } label: {
                Label("Silence", systemImage: "bell.slash")
            }
            .tint(.orange)
        }
    }

    private var stateColor: Color {
        switch alert.state?.lowercased() {
        case "firing": return .red
        case "pending": return .yellow
        default: return .green
        }
    }

    private var severityColor: Color {
        switch alert.severity.lowercased() {
        case "critical": return .red
        case "warning": return .orange
        case "info": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Alert Rule Row

struct AlertRuleRow: View {
    let rule: AlertRule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(ruleStateColor)
                    .frame(width: 8, height: 8)
                Text(rule.displayName)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                if let state = rule.state {
                    Text(state)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let desc = rule.annotations?["description"] ?? rule.annotations?["summary"] {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var ruleStateColor: Color {
        switch rule.state?.lowercased() {
        case "firing": return .red
        case "pending": return .yellow
        case "inactive": return .green
        default: return .gray
        }
    }
}
