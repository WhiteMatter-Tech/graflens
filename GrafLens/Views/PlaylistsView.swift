import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var playlists: [GrafanaPlaylist] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCreate = false

    var body: some View {
        Group {
            if isLoading && playlists.isEmpty {
                ProgressView("Loading playlists...")
            } else if let error = error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            } else if playlists.isEmpty {
                ContentUnavailableView {
                    Label("No Playlists", systemImage: "play.rectangle")
                } description: {
                    Text("No playlists found.")
                }
            } else {
                List {
                    ForEach(playlists) { playlist in
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.displayName)
                                    .font(.body.bold())
                                if let interval = playlist.interval {
                                    Text("Interval: \(interval)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let items = playlist.items {
                                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let uid = playlist.uid {
                                    Task { await deletePlaylist(uid: uid) }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreatePlaylistView(onCreated: { Task { await load() } })
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let client = connectionManager.apiClient else { return }
        isLoading = true
        error = nil
        do {
            playlists = try await client.getPlaylists()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deletePlaylist(uid: String) async {
        guard let client = connectionManager.apiClient else { return }
        do {
            _ = try await client.deletePlaylist(uid: uid)
            HapticManager.success()
            await load()
        } catch {
            HapticManager.error()
        }
    }
}

// MARK: - Create Playlist

struct CreatePlaylistView: View {
    let onCreated: () -> Void

    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var interval = "5m"
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist") {
                    TextField("Name", text: $name)
                    TextField("Interval (e.g. 5m, 10m)", text: $interval)
                        .autocorrectionDisabled()
                }

                if let error = error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(name.isEmpty || interval.isEmpty || isSaving)
                        .bold()
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil

        let playlist = PlaylistCreateRequest(name: name, interval: interval, items: [])

        Task {
            guard let client = connectionManager.apiClient else {
                error = "Not connected"
                isSaving = false
                return
            }
            do {
                _ = try await client.createPlaylist(playlist)
                HapticManager.success()
                onCreated()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                HapticManager.error()
            }
            isSaving = false
        }
    }
}
