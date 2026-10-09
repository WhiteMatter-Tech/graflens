import SwiftUI

struct DashboardDetailView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var webAuthManager: WebAuthManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var viewModel: DashboardDetailViewModel
    @StateObject private var panelCache = PanelSessionCache()
    @State private var selectedTimeRange = TimeRangeOption.sixHours
    @State private var selectedPanel: Panel?
    @State private var showLogin = false
    @State private var showAnnotation = false
    @State private var showSnapshot = false
    @State private var showEdit = false
    @State private var refreshID = 0
    @State private var refreshSeconds = 0

    init(uid: String, title: String) {
        _viewModel = StateObject(wrappedValue: DashboardDetailViewModel(uid: uid, title: title))
    }
    private var allowsNative: Bool { viewModel.dashboard?.allowsNativeRendering ?? false }
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.dashboard == nil {
                ProgressView("Loading dashboard…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.dashboard == nil {
                ContentUnavailableView {
                    Label("Unable to load dashboard", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Try again") { Task { await reload() } }.buttonStyle(.borderedProminent)
                }
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        // Mount every card immediately so native requests and Grafana
                        // pages start together, including rows below the viewport.
                        VStack(alignment: .leading, spacing: 24) {
                            dashboardSummary
                            ForEach(viewModel.dashboard?.sections ?? []) { section in
                                VStack(alignment: .leading, spacing: 16) {
                                    if let title = section.title {
                                        Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 4)
                                    }
                                    ForEach(layoutRows(section.panels, width: geometry.size.width), id: \.id) { row in
                                        HStack(alignment: .top, spacing: row.isNumberRow ? 12 : 16) {
                                            ForEach(row.panels) { panel in
                                                PanelCardView(panel: panel, dashboardUID: viewModel.dashboardUID, timeRange: selectedTimeRange,
                                                    refreshID: refreshID, allowsNative: allowsNative, includeAnnotations: viewModel.dashboard?.hasNativeAnnotations ?? false,
                                                    cache: panelCache, onExpand: { HapticManager.light(); selectedPanel = panel })
                                                    .frame(maxWidth: .infinity)
                                            }
                                            // Keep an odd final metric tile the same width as its neighbors.
                                            ForEach(0..<(row.isNumberRow ? row.capacity - row.panels.count : 0), id: \.self) { _ in
                                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                                            }
                                        }
                                    }
                                }
                            }
                            if viewModel.panels.isEmpty {
                                ContentUnavailableView("No panels", systemImage: "chart.xyaxis.line", description: Text("This dashboard doesn't have any panels yet."))
                            }
                        }
                        .padding(20)
                    }
                    .refreshable { await reload() }
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(viewModel.dashboard?.title ?? viewModel.dashboardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { TimeRangeMenu(selection: $selectedTimeRange) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await reload() } } label: { Label("Refresh dashboard", systemImage: "arrow.clockwise") }
                    Picker("Auto-refresh", selection: $refreshSeconds) {
                        Text("Off").tag(0); Text("Every 30 seconds").tag(30)
                        Text("Every minute").tag(60); Text("Every 5 minutes").tag(300)
                    }
                    Divider()
                    Button { showLogin = true } label: { Label("Sign in to Grafana", systemImage: "person.badge.key") }
                    Button { showAnnotation = true } label: { Label("Add annotation", systemImage: "note.text.badge.plus") }
                    Button { showSnapshot = true } label: { Label("Create snapshot", systemImage: "camera") }
                    Button { showEdit = true } label: { Label("Edit dashboard", systemImage: "pencil") }
                    Button {
                        Task {
                            if let url = await connectionManager.apiClient?.dashboardURL(uid: viewModel.dashboardUID) { await UIApplication.shared.open(url) }
                        }
                    } label: { Label("Open in browser", systemImage: "safari") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Dashboard actions")
            }
        }
        .sheet(item: $selectedPanel) { panel in
            PanelFullScreenView(panel: panel, dashboardUID: viewModel.dashboardUID, timeRange: selectedTimeRange,
                panels: viewModel.panels.filter { $0.type != "row" }, allowsNative: allowsNative, includeAnnotations: viewModel.dashboard?.hasNativeAnnotations ?? false)
        }
        .sheet(isPresented: $showLogin) { GrafanaLoginView() }
        .sheet(isPresented: $showAnnotation) { CreateAnnotationView(dashboardUID: viewModel.dashboardUID, panelId: nil) }
        .sheet(isPresented: $showSnapshot) { CreateSnapshotView(dashboard: viewModel.dashboard, meta: viewModel.meta) }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await reload() } }) {
            if let dashboard = viewModel.dashboard { DashboardEditView(dashboard: dashboard, meta: viewModel.meta) }
        }
        .onChange(of: viewModel.panels.map(\.id)) { _, ids in panelCache.retainPanels(ids) }
        .task {
            guard viewModel.dashboard == nil else { return }
            await viewModel.loadDashboard(client: connectionManager.apiClient)
            if let from = viewModel.dashboard?.time?.from, let range = TimeRangeOption(rawValue: from) { selectedTimeRange = range }
        }
        .task(id: "\(refreshSeconds)-\(scenePhase == .active)") {
            guard refreshSeconds > 0, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(refreshSeconds)) } catch { return }
                guard !Task.isCancelled else { return }
                refreshID += 1
            }
        }
    }
    private var dashboardSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(viewModel.panels.count) panels", systemImage: "square.grid.2x2")
                Spacer()
                if refreshSeconds > 0 { Label("Refresh · \(refreshSeconds)s", systemImage: "arrow.clockwise") }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let description = viewModel.dashboard?.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = viewModel.error {
                Label("Couldn't refresh: \(error)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private func reload() async {
        await viewModel.loadDashboard(client: connectionManager.apiClient)
        refreshID += 1
    }
    private func layoutRows(_ panels: [Panel], width: CGFloat) -> [PanelLayoutRow] {
        var rows: [PanelLayoutRow] = []
        var pending: [Panel] = []
        var previousCapacity = 0
        var previousNumberRow = false
        for panel in panels {
            let compact = panel.isNumberPanel || (panel.type == "gauge" && allowsNative && NativePanelConfiguration.supported(panel) != nil)
            let gauge = ["gauge", "bargauge"].contains(panel.type ?? "")
            let wide = ["table", "logs", "text", "geomap"].contains(panel.type ?? "") || (panel.gridPos?.w ?? 12) >= 18
            let capacity = typeSize.isAccessibilitySize ? 1 : compact
                ? (width < 320 ? 1 : max(2, min(4, Int((width - 28) / 180))))
                : wide ? 1 : gauge ? max(1, min(3, Int((width - 40) / 220)))
                : max(1, min(2, Int(width / 440)))
            if capacity != previousCapacity || compact != previousNumberRow || pending.count == capacity {
                if !pending.isEmpty {
                    rows.append(PanelLayoutRow(panels: pending, capacity: previousCapacity, isNumberRow: previousNumberRow))
                    pending = []
                }
            }
            pending.append(panel); previousCapacity = capacity; previousNumberRow = compact
        }
        if !pending.isEmpty { rows.append(PanelLayoutRow(panels: pending, capacity: previousCapacity, isNumberRow: previousNumberRow)) }
        return rows
    }
}

struct TimeRangeMenu: View {
    @Binding var selection: TimeRangeOption
    var body: some View {
        Menu {
            Picker("Time range", selection: $selection) {
                ForEach(TimeRangeOption.allCases) { option in Text(option.label).tag(option) }
            }
        } label: { HStack(spacing: 5) { Image(systemName: "clock"); Text(selection.label).font(.subheadline.monospacedDigit()) } }
        .accessibilityLabel("Time range, \(selection.label)")
    }
}

// MARK: - Time Range

enum TimeRangeOption: String, CaseIterable, Identifiable {
    case fiveMinutes = "now-5m"
    case fifteenMinutes = "now-15m"
    case thirtyMinutes = "now-30m"
    case oneHour = "now-1h"
    case threeHours = "now-3h"
    case sixHours = "now-6h"
    case twelveHours = "now-12h"
    case twentyFourHours = "now-24h"
    case twoDays = "now-2d"
    case sevenDays = "now-7d"
    case thirtyDays = "now-30d"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .threeHours: return "3h"
        case .sixHours: return "6h"
        case .twelveHours: return "12h"
        case .twentyFourHours: return "24h"
        case .twoDays: return "2d"
        case .sevenDays: return "7d"
        case .thirtyDays: return "30d"
        }
    }
}

private struct PanelLayoutRow: Identifiable {
    let panels: [Panel]
    let capacity: Int
    let isNumberRow: Bool
    var id: Int { panels[0].id }
}
