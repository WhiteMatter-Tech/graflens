import SwiftUI

struct CreateAnnotationView: View {
    let dashboardUID: String
    let panelId: Int?

    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var text = ""
    @State private var tagsText = ""
    @State private var isRange = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Annotation") {
                    TextField("Description", text: $text, axis: .vertical)
                        .lineLimit(3...6)

                    TextField("Tags (comma separated)", text: $tagsText)
                        .autocorrectionDisabled()
                }

                Section("Time") {
                    DatePicker("Start", selection: $startDate)

                    Toggle("Range Annotation", isOn: $isRange)

                    if isRange {
                        DatePicker("End", selection: $endDate)
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
            .navigationTitle("New Annotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.isEmpty || isSaving)
                        .bold()
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil

        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let startMs = Int64(startDate.timeIntervalSince1970 * 1000)
        let endMs: Int64? = isRange ? Int64(endDate.timeIntervalSince1970 * 1000) : nil

        let annotation = AnnotationCreateRequest(
            dashboardUID: dashboardUID,
            panelId: panelId,
            time: startMs,
            timeEnd: endMs,
            text: text,
            tags: tags.isEmpty ? nil : tags
        )

        Task {
            guard let client = connectionManager.apiClient else {
                error = "Not connected"
                isSaving = false
                return
            }
            do {
                _ = try await client.createAnnotation(annotation)
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
