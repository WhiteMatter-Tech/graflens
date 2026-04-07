import SwiftUI

struct SilencesView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var silences: [AlertSilence] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCreateSilence = false

    var body: some View {
        Group {
            if isLoading && silences.isEmpty {
                ProgressView("Loading silences...")
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
            } else if silences.isEmpty {
                ContentUnavailableView {
                    Label("No Silences", systemImage: "bell.slash")
                } description: {
                    Text("No active silences.")
                }
            } else {
                List {
                    ForEach(silences) { silence in
                        SilenceRow(silence: silence, onExpire: { Task { await expireSilence(id: silence.id) } })
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Silences")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreateSilence = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSilence) {
            CreateSilenceView()
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let client = connectionManager.apiClient else { return }
        isLoading = true
        error = nil
        do {
            silences = try await client.getSilences()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func expireSilence(id: String) async {
        guard let client = connectionManager.apiClient else { return }
        do {
            _ = try await client.deleteSilence(id: id)
            HapticManager.success()
            await load()
        } catch {
            HapticManager.error()
        }
    }
}

struct SilenceRow: View {
    let silence: AlertSilence
    let onExpire: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(stateColor)
                    .font(.caption)
                Text(silence.status?.state?.capitalized ?? "Unknown")
                    .font(.caption.bold())
                    .foregroundStyle(stateColor)
                Spacer()
                if let by = silence.createdBy {
                    Text(by)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let comment = silence.comment, !comment.isEmpty {
                Text(comment)
                    .font(.body)
                    .lineLimit(2)
            }

            if let matchers = silence.matchers {
                HStack(spacing: 4) {
                    ForEach(matchers, id: \.name) { matcher in
                        Text("\(matcher.name)=\(matcher.value)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            HStack {
                if let start = silence.startsAt {
                    Text("From: \(start.prefix(19))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let end = silence.endsAt {
                    Text("Until: \(end.prefix(19))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onExpire()
            } label: {
                Label("Expire", systemImage: "xmark.circle")
            }
        }
    }

    private var stateColor: Color {
        switch silence.status?.state?.lowercased() {
        case "active": return .orange
        case "pending": return .yellow
        case "expired": return .secondary
        default: return .secondary
        }
    }
}
