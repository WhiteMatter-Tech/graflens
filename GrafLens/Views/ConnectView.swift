import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var serverURL = "https://play.grafana.org"
    @State private var apiKey = ""
    @State private var connectionName = ""
    @State private var isConnecting = false
    @State private var error: String?
    @State private var showSavedConnections = false
    @State private var useAuthentication = false
    @State private var showLegacyTokenWarning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo area
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis.ascending")
                            .font(.system(size: 64))
                            .foregroundStyle(.orange)

                        Text("GrafLens")
                            .font(.largeTitle.bold())

                        Text("Connect to your dashboard server")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Connection form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Connection Name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("My Grafana (optional)", text: $connectionName)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("https://play.grafana.org", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        Toggle(isOn: $useAuthentication.animation()) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign in with API key")
                                    .font(.subheadline)
                                Text("Not required for public servers")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.orange)
                        .onChange(of: useAuthentication) { _, newValue in
                            if !newValue {
                                apiKey = ""
                            }
                        }

                        if useAuthentication {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Service Account Token")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                SecureField("glsa_xxxxxxxxxxxx", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                if apiKey.hasPrefix("eyJ") {
                                    Label("This looks like an old API key format. Grafana v13+ requires a service account token (glsa_...).", systemImage: "exclamationmark.triangle")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if let error = error {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 4)
                        }

                        Button(action: connect) {
                            HStack {
                                if isConnecting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "link")
                                }
                                Text(isConnecting ? "Connecting..." : "Connect")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(serverURL.isEmpty || isConnecting)
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Saved connections
                    if !connectionManager.connections.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Saved Connections")
                                .font(.headline)

                            ForEach(connectionManager.connections) { conn in
                                Button {
                                    connectToSaved(conn)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(conn.displayName)
                                                .font(.body.bold())
                                            Text(conn.url)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        connectionManager.removeConnection(conn)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    // Help text
                    if useAuthentication {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("How to get an API key", systemImage: "questionmark.circle")
                                .font(.subheadline.bold())

                            Text("1. Go to your Grafana instance")
                            Text("2. Navigate to Administration > Service Accounts")
                            Text("3. Create a new Service Account with Viewer role")
                            Text("4. Generate a token and paste it above")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Try it free", systemImage: "sparkles")
                                .font(.subheadline.bold())
                            Text("Tap Connect to browse the public Grafana demo server. No account or sign-in needed.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Service Account Token Required", isPresented: $showLegacyTokenWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This Grafana server is version 13 or later, which only accepts service account tokens. Old API keys (starting with eyJ...) are no longer valid.\n\nGo to Administration > Service Accounts in Grafana, create a service account, and generate a new token (it will start with glsa_).")
        }
    }

    private func connect() {
        isConnecting = true
        error = nil

        let connection = ServerConnection(
            name: connectionName,
            url: serverURL,
            apiKey: apiKey
        )

        Task {
            do {
                try await connectionManager.connect(to: connection)
                HapticManager.success()
                if let major = connectionManager.serverMajorVersion, major >= 13,
                   !apiKey.isEmpty, !apiKey.hasPrefix("glsa_") {
                    showLegacyTokenWarning = true
                }
            } catch {
                self.error = error.localizedDescription
                HapticManager.error()
            }
            isConnecting = false
        }
    }

    private func connectToSaved(_ connection: ServerConnection) {
        isConnecting = true
        error = nil

        Task {
            do {
                try await connectionManager.connect(to: connection)
                HapticManager.success()
            } catch {
                self.error = error.localizedDescription
                HapticManager.error()
            }
            isConnecting = false
        }
    }
}
