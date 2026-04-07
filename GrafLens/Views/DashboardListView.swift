import SwiftUI

struct DashboardListView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var favoritesManager: FavoritesManager
    @StateObject private var viewModel = DashboardListViewModel()

    var body: some View {
        NavigationStack {
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
            .searchable(text: $viewModel.searchText, prompt: "Search dashboards")
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
        .task {
            if viewModel.dashboards.isEmpty {
                await viewModel.loadDashboards(client: connectionManager.apiClient)
            }
        }
        .onChange(of: viewModel.dashboards) { _, dashboards in
            SpotlightManager.indexDashboards(dashboards)
        }
    }

    private var dashboardList: some View {
        List {
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
                    ForEach(favoritesManager.recentDashboards.prefix(5)) { recent in
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(dashboard.title)
                    .font(.body)
                    .lineLimit(1)

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
                    .foregroundStyle(isFavorite ? .orange : .secondary.opacity(0.4))
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }
}
