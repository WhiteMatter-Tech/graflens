import SwiftUI

struct DashboardEditView: View {
    let dashboard: DashboardDetail
    let meta: DashboardMeta?

    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var title: String
    @State private var description: String
    @State private var tagsText: String
    @State private var isSaving = false
    @State private var error: String?

    init(dashboard: DashboardDetail, meta: DashboardMeta?) {
        self.dashboard = dashboard
        self.meta = meta
        _title = State(initialValue: dashboard.title ?? "")
        _description = State(initialValue: dashboard.description ?? "")
        _tagsText = State(initialValue: (dashboard.tags ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dashboard") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Tags (comma separated)", text: $tagsText)
                        .autocorrectionDisabled()
                }

                Section("Info") {
                    if let folder = meta?.folderTitle {
                        LabeledContent("Folder", value: folder)
                    }
                    if let updated = meta?.updated {
                        LabeledContent("Last Updated", value: String(updated.prefix(10)))
                    }
                    if let by = meta?.updatedBy {
                        LabeledContent("Updated By", value: by)
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
            .navigationTitle("Edit Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.isEmpty || isSaving)
                        .bold()
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil

        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let payload = DashboardSavePayload(
            id: dashboard.id,
            uid: dashboard.uid,
            title: title,
            description: description,
            tags: tags,
            panels: dashboard.panels,
            time: dashboard.time,
            refresh: dashboard.refresh,
            version: nil
        )

        let request = DashboardSaveRequest(
            dashboard: payload,
            folderUid: meta?.folderUid,
            message: "Updated via GrafLens",
            overwrite: true
        )

        Task {
            guard let client = connectionManager.apiClient else {
                error = "Not connected"
                isSaving = false
                return
            }
            do {
                _ = try await client.saveDashboard(request)
                HapticManager.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                HapticManager.error()
            }
            isSaving = false
        }
    }
}
