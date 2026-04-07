import SwiftUI

struct DataSourcesView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var dataSources: [DataSource] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && dataSources.isEmpty {
                    ProgressView("Loading data sources...")
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
                } else if dataSources.isEmpty {
                    ContentUnavailableView {
                        Label("No Data Sources", systemImage: "server.rack")
                    } description: {
                        Text("No data sources configured.")
                    }
                } else {
                    List(dataSources) { ds in
                        HStack {
                            Image(systemName: iconForType(ds.type))
                                .foregroundStyle(.orange)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(ds.name)
                                        .font(.body.bold())
                                    if ds.isDefault == true {
                                        Text("DEFAULT")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundStyle(.orange)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(ds.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let url = ds.url, !url.isEmpty {
                                    Text(url)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Data Sources")
            .refreshable { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = connectionManager.apiClient else { return }
        isLoading = true
        error = nil
        do {
            dataSources = try await client.getDataSources()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("prometheus"): return "flame"
        case let t where t.contains("influx"): return "waveform.path"
        case let t where t.contains("elastic"): return "magnifyingglass"
        case let t where t.contains("mysql"), let t where t.contains("postgres"), let t where t.contains("sql"):
            return "cylinder"
        case let t where t.contains("loki"): return "doc.text"
        case let t where t.contains("tempo"): return "point.3.connected.trianglepath.dotted"
        case let t where t.contains("cloudwatch"): return "cloud"
        default: return "server.rack"
        }
    }
}
