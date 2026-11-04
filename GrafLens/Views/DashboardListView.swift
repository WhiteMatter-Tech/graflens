import SwiftUI

struct DashboardListView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var favoritesManager: FavoritesManager
    @StateObject private var viewModel = DashboardListViewModel()

    @State private var path: [DashboardSearchResult] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isLoading && viewModel.dashboards.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading dashboards...")
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
                            Task { await viewModel.loadDashboards(client: connectionManager.apiClient) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                } else if viewModel.dashboards.isEmpty {
                    ContentUnavailableView {
                        Label("No Dashboards", systemImage: "square.grid.2x2.fill")
                    } description: {
                        Text("No dashboards found on this Grafana instance.")
                    }
                } else {
                    dashboardList
                }
            }
            .navigationTitle("Dashboards")
            .searchable(text: $viewModel.searchText, prompt: "Search dashboards, folders, or tags")
            .refreshable {
                await viewModel.loadDashboards(client: connectionManager.apiClient)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ServerSwitcherMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.light()
                        Task { await viewModel.loadDashboards(client: connectionManager.apiClient) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task(id: connectionManager.activeConnection?.id) {
            await viewModel.loadDashboards(client: connectionManager.apiClient)
        }
        .onChange(of: viewModel.dashboards) { _, dashboards in
            SpotlightManager.indexDashboards(dashboards)
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            let uidIndex = args.firstIndex(of: "--fixture-dashboard-uid").map { args.index(after: $0) }
            let uid = uidIndex.flatMap { args.indices.contains($0) ? args[$0] : nil }
            if args.contains("--fixture-server"), args.contains("--fixture-dashboard"), path.isEmpty,
               let dashboard = uid.flatMap({ uid in dashboards.first { $0.uid == uid } }) ?? dashboards.first { path = [dashboard] }
            #endif
        }
    }

    private var dashboardList: some View {
        List {
            if viewModel.searchText.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your observatory").font(.title2.weight(.semibold))
                        Text("\(viewModel.dashboards.count) \(viewModel.dashboards.count == 1 ? "dashboard" : "dashboards") across \(viewModel.folderOrder.count) \(viewModel.folderOrder.count == 1 ? "folder" : "folders")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
            }
            // Favorites section
            let favorites = viewModel.dashboards.filter { favoritesManager.isFavorite($0.uid) }
            if !favorites.isEmpty && viewModel.searchText.isEmpty {
                Section {
                    ForEach(favorites) { dashboard in
                        NavigationLink(value: dashboard) {
                            DashboardRow(dashboard: dashboard, isFavorite: true, onToggleFavorite: {
                                HapticManager.selection()
                                favoritesManager.toggleFavorite(dashboard.uid)
                            })
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                        Text("Favorites")
                    }
                }
            }

            // Recents section
            if !favoritesManager.recentDashboards.isEmpty && viewModel.searchText.isEmpty {
                Section {
                    ForEach(favoritesManager.recentDashboards.filter { !favoritesManager.isFavorite($0.uid) }.prefix(3)) { recent in
                        if let dashboard = viewModel.dashboards.first(where: { $0.uid == recent.uid }) {
                            NavigationLink(value: dashboard) {
                                DashboardRow(dashboard: dashboard, isFavorite: favoritesManager.isFavorite(dashboard.uid), onToggleFavorite: {
                                    HapticManager.selection()
                                    favoritesManager.toggleFavorite(dashboard.uid)
                                })
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("Recent")
                    }
                }
            }

            // All dashboards by folder
            ForEach(viewModel.filteredFolderOrder, id: \.self) { folder in
                Section {
                    ForEach(viewModel.filteredDashboards(in: folder)) { dashboard in
                        NavigationLink(value: dashboard) {
                            DashboardRow(dashboard: dashboard, isFavorite: favoritesManager.isFavorite(dashboard.uid), onToggleFavorite: {
                                HapticManager.selection()
                                favoritesManager.toggleFavorite(dashboard.uid)
                            })
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: folder == "General" ? "folder" : "folder.fill")
                        Text(folder)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !viewModel.searchText.isEmpty && viewModel.filteredFolderOrder.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        }
        .navigationDestination(for: DashboardSearchResult.self) { dashboard in
            DashboardDetailView(uid: dashboard.uid, title: dashboard.title)
                .onAppear {
                    favoritesManager.recordVisit(uid: dashboard.uid, title: dashboard.title, folderTitle: dashboard.folderTitle)
                }
        }
    }
}

struct DashboardRow: View {
    let dashboard: DashboardSearchResult
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 42, height: 42)
                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(dashboard.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                if let tags = dashboard.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)

            Spacer()

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .orange : .secondary)
                    .font(.body)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove \(dashboard.title) from favorites" : "Add \(dashboard.title) to favorites")
        }
        .padding(.vertical, 4)
    }
}
