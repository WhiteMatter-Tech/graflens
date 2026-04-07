import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var webAuthManager: WebAuthManager
    @EnvironmentObject var storeManager: StoreManager
    @EnvironmentObject var appearanceManager: AppearanceManager
    @EnvironmentObject var favoritesManager: FavoritesManager
    @State private var orgInfo: GrafanaOrg?
    @State private var healthInfo: GrafanaHealth?
    @State private var showDisconnectConfirm = false
    @State private var showLogin = false
    @State private var showTipJar = false
    @State private var showClearCacheConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // Connection info
                if let connection = connectionManager.activeConnection {
                    Section("Active Connection") {
                        LabeledContent("Name", value: connection.displayName)
                        LabeledContent("URL", value: connection.url)
                        LabeledContent("API Auth", value: "Service Account Token")
                    }
                }

                // Web session
                Section {
                    HStack {
                        Text("Browser Session")
                        Spacer()
                        if webAuthManager.isAuthenticated {
                            Label("Signed In", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("Not Signed In", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    if webAuthManager.isAuthenticated {
                        Button {
                            HapticManager.medium()
                            webAuthManager.clearSession()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Clear Browser Session")
                            }
                        }
                    } else {
                        Button {
                            showLogin = true
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.key")
                                Text("Sign In for Panel Viewing")
                            }
                        }
                        .tint(.orange)
                    }
                } header: {
                    Text("Panel Rendering")
                } footer: {
                    Text("Panels are rendered via embedded web views. If your Grafana uses OIDC/OAuth (e.g. Authentik), you need to sign in here so panels can load.")
                }

                // Server info
                if let health = healthInfo {
                    Section("Server Info") {
                        if let version = health.version {
                            LabeledContent("Grafana Version", value: version)
                        }
                        if let db = health.database {
                            LabeledContent("Database", value: db)
                        }
                    }
                }

                if let org = orgInfo {
                    Section("Organization") {
                        LabeledContent("Name", value: org.name)
                        LabeledContent("ID", value: "\(org.id)")
                    }
                }

                // Management links
                Section("Manage") {
                    NavigationLink(destination: FolderManagementView()) {
                        Label("Folders", systemImage: "folder")
                    }
                    NavigationLink(destination: PlaylistsView()) {
                        Label("Playlists", systemImage: "play.rectangle")
                    }
                    NavigationLink(destination: SnapshotsView()) {
                        Label("Snapshots", systemImage: "camera")
                    }
                    NavigationLink(destination: SilencesView()) {
                        Label("Alert Silences", systemImage: "bell.slash")
                    }
                }

                // Saved connections
                Section("Saved Connections") {
                    ForEach(connectionManager.connections) { conn in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(conn.displayName)
                                    .font(.body)
                                Text(conn.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if conn.id == connectionManager.activeConnection?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            connectionManager.removeConnection(connectionManager.connections[index])
                        }
                    }
                }

                // Appearance
                Section("Appearance") {
                    Picker(selection: $appearanceManager.mode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.icon)
                                .tag(mode)
                        }
                    } label: {
                        Label("Theme", systemImage: "paintbrush")
                    }
                }

                // Data
                Section("Data") {
                    Button {
                        showClearCacheConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundStyle(.orange)
                            Text("Clear Panel Cache")
                        }
                    }

                    Button {
                        SpotlightManager.deindexAll()
                        HapticManager.success()
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.orange)
                            Text("Clear Spotlight Index")
                        }
                    }

                    LabeledContent("Favorites", value: "\(favoritesManager.favoriteUIDs.count)")
                    LabeledContent("Recent Dashboards", value: "\(favoritesManager.recentDashboards.count)")
                }

                // Tip jar
                Section {
                    Button {
                        showTipJar = true
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.orange)
                            Text("Tip Jar")
                            Spacer()
                            if storeManager.totalTips > 0 {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Button {
                        if let url = URL(string: "https://github.com/whitematter-tech/graflens") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(.orange)
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("GrafLens is free and open source. Tips help support continued development.")
                }

                // Actions
                Section {
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "link.badge.plus")
                                .rotationEffect(.degrees(45))
                            Text("Disconnect")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .confirmationDialog("Disconnect?", isPresented: $showDisconnectConfirm) {
                Button("Disconnect", role: .destructive) {
                    HapticManager.medium()
                    webAuthManager.clearSession()
                    connectionManager.disconnect()
                }
            } message: {
                Text("You will be returned to the connection screen.")
            }
            .confirmationDialog("Clear Cache?", isPresented: $showClearCacheConfirm) {
                Button("Clear", role: .destructive) {
                    Task {
                        await PanelCacheManager.shared.clearCache()
                        HapticManager.success()
                    }
                }
            } message: {
                Text("This will remove all cached panel images.")
            }
            .sheet(isPresented: $showLogin) {
                GrafanaLoginView()
            }
            .sheet(isPresented: $showTipJar) {
                TipJarView()
            }
        }
        .task { await loadServerInfo() }
    }

    private func loadServerInfo() async {
        guard let client = connectionManager.apiClient else { return }
        do {
            async let health = client.checkHealth()
            async let org = client.getCurrentOrg()
            healthInfo = try await health
            orgInfo = try? await org
        } catch {
            // Non-critical, ignore
        }
    }
}
