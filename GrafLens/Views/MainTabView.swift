import SwiftUI

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPhone Tab Layout

    private var iPhoneLayout: some View {
        TabView {
            DashboardListView()
                .tabItem {
                    Label("Dashboards", systemImage: "square.grid.2x2")
                }

            AlertsView()
                .tabItem {
                    Label("Alerts", systemImage: "bell.badge")
                }

            DataSourcesView()
                .tabItem {
                    Label("Data Sources", systemImage: "server.rack")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.orange)
    }

    // MARK: - iPad Sidebar Layout

    @State private var selectedTab: SidebarTab? = .dashboards

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Browse") {
                    Label("Dashboards", systemImage: "square.grid.2x2")
                        .tag(SidebarTab.dashboards)
                    Label("Alerts", systemImage: "bell.badge")
                        .tag(SidebarTab.alerts)
                    Label("Data Sources", systemImage: "server.rack")
                        .tag(SidebarTab.dataSources)
                }

                Section("Manage") {
                    Label("Folders", systemImage: "folder")
                        .tag(SidebarTab.folders)
                    Label("Playlists", systemImage: "play.rectangle")
                        .tag(SidebarTab.playlists)
                    Label("Snapshots", systemImage: "camera")
                        .tag(SidebarTab.snapshots)
                }

                Section {
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarTab.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("GrafLens")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ServerSwitcherMenu()
                }
            }
        } detail: {
            switch selectedTab {
            case .dashboards:
                DashboardListView()
            case .alerts:
                AlertsView()
            case .dataSources:
                DataSourcesView()
            case .folders:
                NavigationStack { FolderManagementView() }
            case .playlists:
                NavigationStack { PlaylistsView() }
            case .snapshots:
                NavigationStack { SnapshotsView() }
            case .settings:
                SettingsView()
            case .none:
                Text("Select an item")
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.orange)
    }
}

enum SidebarTab: String, Hashable {
    case dashboards, alerts, dataSources, folders, playlists, snapshots, settings
}
