import SwiftUI

// MARK: - View Model

@MainActor
class SyntheticsViewModel: ObservableObject {
    @Published var checks: [SyntheticCheck] = []
    @Published var stats: [String: SyntheticCheckStats] = [:]
    @Published var isLoading = false
    @Published var error: String?
    @Published var smUnavailable = false

    func load(client: GrafanaAPIClient?) async {
        guard let client = client else { return }
        isLoading = true
        error = nil
        smUnavailable = false

        do {
            checks = try await client.getSyntheticChecks()
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch GrafanaAPIError.notFound {
            checks = []
            smUnavailable = true
            isLoading = false
            return
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return
        }

        await loadStats(client: client)
        isLoading = false
    }

    /// Best-effort overlay of live status, 24h uptime, and latency from
    /// Prometheus. Any failure leaves `stats` empty and the list still renders.
    private func loadStats(client: GrafanaAPIClient) async {
        guard let ds = await client.prometheusDatasource() else { return }

        async let status = client.querySyntheticMetric(
            expr: "min by (job, instance) (probe_success)",
            datasourceUID: ds.uid, datasourceType: ds.type)
        async let uptime = client.querySyntheticMetric(
            expr: "100 * sum by (job, instance) (increase(probe_all_success_sum[24h])) / sum by (job, instance) (increase(probe_all_success_count[24h]))",
            datasourceUID: ds.uid, datasourceType: ds.type)
        async let duration = client.querySyntheticMetric(
            expr: "avg by (job, instance) (avg_over_time(probe_duration_seconds[1h]))",
            datasourceUID: ds.uid, datasourceType: ds.type)

        let statusSamples = await status
        let uptimeSamples = await uptime
        let durationSamples = await duration

        func key(_ sample: SyntheticMetricSample) -> String? {
            guard let job = sample.labels["job"], let instance = sample.labels["instance"] else { return nil }
            return SyntheticCheck.metricKey(job: job, instance: instance)
        }

        var merged: [String: SyntheticCheckStats] = [:]
        for sample in statusSamples {
            guard let k = key(sample) else { continue }
            merged[k, default: SyntheticCheckStats()].up = sample.value >= 1
        }
        for sample in uptimeSamples where sample.value.isFinite {
            guard let k = key(sample) else { continue }
            merged[k, default: SyntheticCheckStats()].uptimePercent = sample.value
        }
        for sample in durationSamples where sample.value.isFinite {
            guard let k = key(sample) else { continue }
            merged[k, default: SyntheticCheckStats()].avgDurationSeconds = sample.value
        }
        stats = merged
    }
}

// MARK: - Synthetics View

struct SyntheticsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @StateObject private var viewModel = SyntheticsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.checks.isEmpty {
                    ProgressView("Loading synthetics...")
                } else if viewModel.smUnavailable {
                    ContentUnavailableView {
                        Label("Synthetic Monitoring Not Found", systemImage: "waveform.path.ecg")
                    } description: {
                        Text("This Grafana instance doesn't have the Synthetic Monitoring app installed, or the service account can't access it.")
                    }
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
                } else if viewModel.checks.isEmpty {
                    ContentUnavailableView {
                        Label("No Checks", systemImage: "waveform.path.ecg")
                    } description: {
                        Text("No synthetic monitoring checks are configured.")
                    }
                } else {
                    checkList
                }
            }
            .navigationTitle("Synthetics")
            .refreshable { await viewModel.load(client: connectionManager.apiClient) }
        }
        .task { await viewModel.load(client: connectionManager.apiClient) }
    }

    private var checkList: some View {
        List {
            ForEach(orderedTypes, id: \.self) { type in
                Section(sectionTitle(for: type)) {
                    ForEach(checks(ofType: type)) { check in
                        SyntheticCheckRow(check: check, stats: viewModel.stats[check.metricKey])
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var orderedTypes: [String] {
        var seen: [String] = []
        for check in viewModel.checks where !seen.contains(check.checkType) {
            seen.append(check.checkType)
        }
        return seen
    }

    private func checks(ofType type: String) -> [SyntheticCheck] {
        viewModel.checks.filter { $0.checkType == type }
    }

    private func sectionTitle(for type: String) -> String {
        let matches = checks(ofType: type)
        let name = matches.first?.typeDisplayName ?? type
        return "\(name) (\(matches.count))"
    }
}

// MARK: - Check Row

struct SyntheticCheckRow: View {
    let check: SyntheticCheck
    let stats: SyntheticCheckStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Image(systemName: check.typeSymbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(check.displayName)
                    .font(.body.bold())
                    .lineLimit(1)
                Spacer()
                if !check.enabled {
                    Text("disabled")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }

            Text(check.target)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 12) {
                if let uptime = stats?.uptimePercent {
                    metric(icon: "checkmark.circle", text: String(format: "%.2f%%", uptime), tint: uptimeColor(uptime))
                }
                if let duration = stats?.avgDurationSeconds {
                    metric(icon: "clock", text: formatDuration(duration), tint: .secondary)
                }
                if let frequency = check.frequencyDescription {
                    metric(icon: "arrow.clockwise", text: frequency, tint: .secondary)
                }
                if check.probeCount > 0 {
                    metric(icon: "dot.radiowaves.left.and.right", text: "\(check.probeCount)", tint: .secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func metric(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(tint)
    }

    private var statusColor: Color {
        guard check.enabled else { return .secondary }
        switch stats?.up {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .gray
        }
    }

    private func uptimeColor(_ uptime: Double) -> Color {
        switch uptime {
        case 99...: return .green
        case 95..<99: return .orange
        default: return .red
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 { return String(format: "%.0fms", seconds * 1000) }
        return String(format: "%.2fs", seconds)
    }
}
