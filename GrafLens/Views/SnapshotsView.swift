import SwiftUI

struct SnapshotsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var snapshots: [SnapshotListItem] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && snapshots.isEmpty {
                ProgressView("Loading snapshots...")
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
            } else if snapshots.isEmpty {
                ContentUnavailableView {
                    Label("No Snapshots", systemImage: "camera")
                } description: {
                    Text("No dashboard snapshots found.")
                }
            } else {
                List {
                    ForEach(snapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot, onDelete: { Task { await deleteSnapshot(key: snapshot.key ?? "") } })
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Snapshots")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let client = connectionManager.apiClient else { return }
        isLoading = true
        error = nil
        do {
            snapshots = try await client.getSnapshots()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteSnapshot(key: String) async {
        guard let client = connectionManager.apiClient else { return }
        do {
            _ = try await client.deleteSnapshot(key: key)
            HapticManager.success()
            await load()
        } catch {
            HapticManager.error()
        }
    }
}

struct SnapshotRow: View {
    let snapshot: SnapshotListItem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.name ?? "Snapshot \(snapshot.id)")
                .font(.body.bold())
                .lineLimit(1)

            if let url = snapshot.externalUrl, !url.isEmpty {
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }

            HStack {
                if let created = snapshot.created {
                    Text("Created: \(created.prefix(10))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let expires = snapshot.expires {
                    Text("Expires: \(expires.prefix(10))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Create Snapshot Sheet

struct CreateSnapshotView: View {
    let dashboard: DashboardDetail?
    let meta: DashboardMeta?

    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var expiration: SnapshotExpiry = .sevenDays
    @State private var isSaving = false
    @State private var snapshotURL: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dashboard") {
                    LabeledContent("Name", value: dashboard?.title ?? "Unknown")
                }

                Section("Expiration") {
                    Picker("Expires in", selection: $expiration) {
                        ForEach(SnapshotExpiry.allCases) { exp in
                            Text(exp.label).tag(exp)
                        }
                    }
                }

                if let url = snapshotURL {
                    Section("Snapshot Created") {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Button("Copy URL") {
                            UIPasteboard.general.string = url
                            HapticManager.success()
                        }
                    }
                }

                if let error = error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(snapshotURL != nil ? "Done" : "Create") {
                        if snapshotURL != nil { dismiss() } else { create() }
                    }
                    .disabled(isSaving)
                    .bold()
                }
            }
        }
    }

    private func create() {
        guard let dashboard = dashboard else { return }
        isSaving = true
        error = nil

        let payload = DashboardSavePayload(
            id: dashboard.id,
            uid: dashboard.uid,
            title: dashboard.title,
            description: dashboard.description,
            tags: dashboard.tags,
            panels: dashboard.panels,
            time: dashboard.time,
            refresh: dashboard.refresh,
            version: nil
        )

        let request = SnapshotCreateRequest(dashboard: payload, expires: expiration.seconds)

        Task {
            guard let client = connectionManager.apiClient else {
                error = "Not connected"
                isSaving = false
                return
            }
            do {
                let response = try await client.createSnapshot(request)
                snapshotURL = response.url
                HapticManager.success()
            } catch {
                self.error = error.localizedDescription
                HapticManager.error()
            }
            isSaving = false
        }
    }
}

enum SnapshotExpiry: String, CaseIterable, Identifiable {
    case oneHour, oneDay, sevenDays, thirtyDays, never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .never: return "Never"
        }
    }

    var seconds: Int? {
        switch self {
        case .oneHour: return 3600
        case .oneDay: return 86400
        case .sevenDays: return 604800
        case .thirtyDays: return 2592000
        case .never: return nil
        }
    }
}
