import SwiftUI

struct CreateSilenceView: View {
    let alertInstance: GrafanaAlertInstance?

    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var comment = ""
    @State private var createdBy = "GrafLens"
    @State private var duration: SilenceDuration = .oneHour
    @State private var customEnd = Date().addingTimeInterval(3600)
    @State private var matcherName = "alertname"
    @State private var matcherValue = ""
    @State private var isSaving = false
    @State private var error: String?

    init(alertInstance: GrafanaAlertInstance? = nil) {
        self.alertInstance = alertInstance
        if let alert = alertInstance {
            _matcherValue = State(initialValue: alert.alertName)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Silence") {
                    TextField("Comment", text: $comment, axis: .vertical)
                        .lineLimit(2...4)

                    TextField("Created by", text: $createdBy)
                }

                Section("Duration") {
                    Picker("Duration", selection: $duration) {
                        ForEach(SilenceDuration.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }

                    if duration == .custom {
                        DatePicker("End time", selection: $customEnd)
                    }
                }

                Section("Matcher") {
                    TextField("Label name", text: $matcherName)
                        .autocorrectionDisabled()
                    TextField("Label value", text: $matcherValue)
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
            .navigationTitle("Create Silence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(comment.isEmpty || matcherValue.isEmpty || isSaving)
                        .bold()
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil

        let formatter = ISO8601DateFormatter()
        let now = Date()
        let endDate: Date = duration == .custom ? customEnd : now.addingTimeInterval(duration.seconds)

        let silence = SilenceCreateRequest(
            matchers: [SilenceMatcher(name: matcherName, value: matcherValue, isRegex: false, isEqual: true)],
            startsAt: formatter.string(from: now),
            endsAt: formatter.string(from: endDate),
            createdBy: createdBy,
            comment: comment
        )

        Task {
            guard let client = connectionManager.apiClient else {
                error = "Not connected"
                isSaving = false
                return
            }
            do {
                _ = try await client.createSilence(silence)
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

enum SilenceDuration: String, CaseIterable, Identifiable {
    case thirtyMinutes, oneHour, twoHours, fourHours, eightHours, twentyFourHours, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .eightHours: return "8 hours"
        case .twentyFourHours: return "24 hours"
        case .custom: return "Custom"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .thirtyMinutes: return 1800
        case .oneHour: return 3600
        case .twoHours: return 7200
        case .fourHours: return 14400
        case .eightHours: return 28800
        case .twentyFourHours: return 86400
        case .custom: return 3600
        }
    }
}
