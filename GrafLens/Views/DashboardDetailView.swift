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
                VStack(spacing: 0) {
                if !viewModel.variables.isEmpty {
                    VariableBar(viewModel: viewModel)
                    Divider()
                }
                GeometryReader { geometry in
                    let layout = dashboardLayout(in: geometry)
                    ScrollView {
                        // Mount every card immediately so native requests and Grafana
                        // pages start together, including rows below the viewport.
                        VStack(alignment: .leading, spacing: 24) {
                            dashboardSummary
                                .frame(width: layout.division == nil ? nil : layout.trailingWidth)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            ForEach(viewModel.dashboard?.sections ?? []) { section in
                                VStack(alignment: .leading, spacing: 16) {
                                    if let title = section.title {
                                        Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 4)
                                            .frame(width: layout.division == nil ? nil : layout.trailingWidth, alignment: .leading)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    ForEach(layoutRows(section.panels, layout: layout), id: \.id) { row in
                                        let spacing: CGFloat = row.isNumberRow ? 12 : 16
                                        HStack(alignment: .top, spacing: 0) {
                                            ForEach(0..<row.capacity, id: \.self) { index in
                                                Group {
                                                    if index < row.panels.count {
                                                        let panel = row.panels[index]
                                                        PanelCardView(panel: panel, dashboardUID: viewModel.dashboardUID, timeRange: selectedTimeRange,
                                                            refreshID: refreshID, allowsNative: allowsNative, includeAnnotations: viewModel.dashboard?.hasNativeAnnotations ?? false,
                                                            variables: viewModel.variableParams, cache: panelCache, onExpand: { HapticManager.light(); selectedPanel = panel })
                                                            .id(panel.id)
                                                    } else {
                                                        Color.clear.frame(height: 0)
                                                    }
                                                }
                                                .frame(width: layout.panelWidth(at: index, capacity: row.capacity, spacing: spacing))
                                                if index < row.capacity - 1 {
                                                    Color.clear.frame(width: layout.gap(after: index, capacity: row.capacity, spacing: spacing), height: 0)
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                panels: viewModel.panels.filter { $0.type != "row" }, allowsNative: allowsNative, includeAnnotations: viewModel.dashboard?.hasNativeAnnotations ?? false,
                variables: viewModel.variableParams)
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
    private func dashboardLayout(in geometry: GeometryProxy) -> DashboardLayout {
        if #available(iOS 27.1, *) {
            // Horizontal folds remain under the system ScrollView's handling.
            // For a book pose, keep each card entirely on one side of the fold.
            let division = geometry.reservedRegions(kind: .division).first {
                $0.frame.height > $0.frame.width
            }.map { region in
                region.frame.insetBy(dx: -max(region.margins.leading, region.margins.trailing), dy: 0)
            }
            return DashboardLayout(width: geometry.size.width, division: division)
        }
        return DashboardLayout(width: geometry.size.width)
    }

    private func layoutRows(_ panels: [Panel], layout: DashboardLayout) -> [PanelLayoutRow] {
        var rows: [PanelLayoutRow] = []
        var pending: [Panel] = []
        var previousCapacity = 0
        var previousNumberRow = false
        for panel in panels {
            let compact = panel.isNumberPanel || (panel.type == "gauge" && allowsNative && NativePanelConfiguration.supported(panel) != nil)
            let gauge = ["gauge", "bargauge"].contains(panel.type ?? "")
            let wide = ["table", "logs", "text", "geomap"].contains(panel.type ?? "") || (panel.gridPos?.w ?? 12) >= 18
            let capacity = layout.capacity(compact: compact, gauge: gauge, wide: wide, accessible: typeSize.isAccessibilitySize)
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
