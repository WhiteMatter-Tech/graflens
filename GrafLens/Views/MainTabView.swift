import SwiftUI

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        if #available(iOS 18.0, *) {
            adaptiveLayout
        } else if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // Keep one navigation tree as a fold changes size classes. The system
    // adapts tabs, the sidebar, and reserved camera/hinge regions in place.
    @State private var adaptiveTab: SidebarTab = .dashboards

    @available(iOS 18.0, *)
    private var adaptiveLayout: some View {
        TabView(selection: $adaptiveTab) {
            Tab("Dashboards", systemImage: "square.grid.2x2", value: .dashboards) {
                DashboardListView()
            }
            Tab("Alerts", systemImage: "bell.badge", value: .alerts) {
                AlertsView()
            }
            Tab("Synthetics", systemImage: "waveform.path.ecg", value: .synthetics) {
                SyntheticsView()
            }
            Tab("Data Sources", systemImage: "server.rack", value: .dataSources) {
                DataSourcesView()
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
            TabSection("Manage") {
                Tab("Folders", systemImage: "folder", value: SidebarTab.folders) {
                    NavigationStack { FolderManagementView() }
                }
                Tab("Playlists", systemImage: "play.rectangle", value: SidebarTab.playlists) {
                    NavigationStack { PlaylistsView() }
                }
                Tab("Snapshots", systemImage: "camera", value: SidebarTab.snapshots) {
                    NavigationStack { SnapshotsView() }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.orange)
        #if DEBUG
        // Screenshot capture: `--initial-tab alerts` opens that tab at launch.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--initial-tab"), args.indices.contains(index + 1),
               let tab = SidebarTab(rawValue: args[index + 1]) {
                adaptiveTab = tab
            }
        }
        #endif
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

            SyntheticsView()
                .tabItem {
                    Label("Synthetics", systemImage: "waveform.path.ecg")
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
                Section {
                    ServerSwitcherMenu().padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                Section("Browse") {
                    Label("Dashboards", systemImage: "square.grid.2x2")
                        .tag(SidebarTab.dashboards)
                    Label("Alerts", systemImage: "bell.badge")
                        .tag(SidebarTab.alerts)
                    Label("Synthetics", systemImage: "waveform.path.ecg")
                        .tag(SidebarTab.synthetics)
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
        } detail: {
            switch selectedTab {
            case .dashboards:
                DashboardListView()
            case .alerts:
                AlertsView()
            case .synthetics:
                SyntheticsView()
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
    case dashboards, alerts, synthetics, dataSources, folders, playlists, snapshots, settings
}
