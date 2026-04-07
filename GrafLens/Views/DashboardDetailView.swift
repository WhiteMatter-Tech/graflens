import SwiftUI

struct DashboardDetailView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var webAuthManager: WebAuthManager
    @StateObject private var viewModel: DashboardDetailViewModel
    @State private var selectedTimeRange = TimeRangeOption.sixHours
    @State private var selectedPanel: Panel?
    @State private var showLogin = false
    @State private var showAnnotation = false
    @State private var showSnapshot = false
    @State private var showEdit = false

    init(uid: String, title: String) {
        _viewModel = StateObject(wrappedValue: DashboardDetailViewModel(uid: uid, title: title))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading dashboard...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadDashboard(client: connectionManager.apiClient) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            } else {
                panelGrid
            }
        }
        .navigationTitle(viewModel.dashboardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(TimeRangeOption.allCases) { option in
                        Button {
                            selectedTimeRange = option
                            HapticManager.selection()
                        } label: {
                            HStack {
                                Text(option.label)
                                if selectedTimeRange == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(selectedTimeRange.label)
                            .font(.caption)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAnnotation = true } label: {
                        Label("Add Annotation", systemImage: "note.text.badge.plus")
                    }
                    Button { showSnapshot = true } label: {
                        Label("Create Snapshot", systemImage: "camera")
                    }
                    Button { showEdit = true } label: {
                        Label("Edit Dashboard", systemImage: "pencil")
                    }
                    Divider()
                    Button {
                        Task {
                            if let client = connectionManager.apiClient,
                               let url = await client.dashboardURL(uid: viewModel.dashboardUID) {
                                await UIApplication.shared.open(url)
                            }
                        }
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $selectedPanel) { panel in
            PanelFullScreenView(
                panel: panel,
                dashboardUID: viewModel.dashboardUID,
                timeRange: selectedTimeRange,
                panels: viewModel.panels.filter { $0.isVisualization }
            )
        }
        .sheet(isPresented: $showLogin) {
            GrafanaLoginView()
        }
        .sheet(isPresented: $showAnnotation) {
            CreateAnnotationView(dashboardUID: viewModel.dashboardUID, panelId: nil)
        }
        .sheet(isPresented: $showSnapshot) {
            CreateSnapshotView(dashboard: viewModel.dashboard, meta: viewModel.meta)
        }
        .sheet(isPresented: $showEdit) {
            if let dashboard = viewModel.dashboard {
                DashboardEditView(dashboard: dashboard, meta: viewModel.meta)
            }
        }
        .task {
            await viewModel.loadDashboard(client: connectionManager.apiClient)
        }
    }

    private var panelGrid: some View {
        ScrollView {
            // Show sign-in banner if not web-authenticated
            if !webAuthManager.isAuthenticated {
                signInBanner
            }

            if let description = viewModel.dashboard?.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            LazyVStack(spacing: 12) {
                ForEach(viewModel.panels.filter { $0.isVisualization }) { panel in
                    PanelCardView(
                        panel: panel,
                        dashboardUID: viewModel.dashboardUID,
                        timeRange: selectedTimeRange
                    )
                    .onTapGesture {
                        HapticManager.light()
                        selectedPanel = panel
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var signInBanner: some View {
        Button {
            showLogin = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to view panels")
                        .font(.subheadline.bold())
                    Text("Authenticate with your Grafana instance to render panels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 8)
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
