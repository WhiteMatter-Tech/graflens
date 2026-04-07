import SwiftUI

struct FolderManagementView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var folders: [GrafanaFolder] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var newFolderTitle = ""
    @State private var isCreating = false

    var body: some View {
        Group {
            if isLoading && folders.isEmpty {
                ProgressView("Loading folders...")
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
            } else {
                List {
                    ForEach(folders) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(folder.title)
                                    .font(.body)
                                Text(folder.uid)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await deleteFolder(uid: folder.uid) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Folder", isPresented: $showCreate) {
            TextField("Folder name", text: $newFolderTitle)
            Button("Cancel", role: .cancel) { newFolderTitle = "" }
            Button("Create") { Task { await createFolder() } }
                .disabled(newFolderTitle.isEmpty)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let client = connectionManager.apiClient else { return }
        isLoading = true
        error = nil
        do {
            folders = try await client.getFolders()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func createFolder() async {
        guard let client = connectionManager.apiClient else { return }
        guard !newFolderTitle.isEmpty else { return }
        isCreating = true
        do {
            _ = try await client.createFolder(FolderCreateRequest(title: newFolderTitle, uid: nil))
            newFolderTitle = ""
            HapticManager.success()
            await load()
        } catch {
            HapticManager.error()
        }
        isCreating = false
    }

    private func deleteFolder(uid: String) async {
        guard let client = connectionManager.apiClient else { return }
        do {
            _ = try await client.deleteFolder(uid: uid)
            HapticManager.success()
            await load()
        } catch {
            HapticManager.error()
        }
    }
}
