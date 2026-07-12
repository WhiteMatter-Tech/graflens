import SwiftUI
import WebKit

struct PanelCardView: View {
    let panel: Panel
    let dashboardUID: String
    let timeRange: TimeRangeOption
    var variables: [String: [String]] = [:]
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var webAuthManager: WebAuthManager
    @EnvironmentObject var appearanceManager: AppearanceManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showShareSheet = false
    @State private var snapshotImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Text(panel.displayTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                if let type = panel.type {
                    Text(type)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                Button {
                    HapticManager.light()
                    captureAndShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Panel content via WebView
            if let client = connectionManager.apiClient {
                GrafanaPanelWebView(
                    client: client,
                    webAuthManager: webAuthManager,
                    dashboardUID: dashboardUID,
                    panelID: panel.id,
                    from: timeRange.rawValue,
                    to: "now",
                    theme: currentTheme,
                    variables: variables,
                    onSnapshot: { image in
                        snapshotImage = image
                        // Cache for the widget to display.
                        if let data = image.jpegData(compressionQuality: 0.85) {
                            SharedDataManager.savePanelSnapshot(
                                dashboardUID: dashboardUID,
                                panelID: panel.id,
                                imageData: data
                            )
                        }
                    }
                )
                .frame(height: panelHeight)
            } else {
                placeholderView
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .sheet(isPresented: $showShareSheet) {
            if let image = snapshotImage {
                ShareSheetView(items: [image])
            }
        }
    }

    private var currentTheme: String {
        switch appearanceManager.mode {
        case .dark: return "dark"
        case .light: return "light"
        case .system: return colorScheme == .dark ? "dark" : "light"
        }
    }

    private var panelHeight: CGFloat {
        guard let gridPos = panel.gridPos, let h = gridPos.h else {
            return 250
        }
        return max(CGFloat(h) * 30, 150)
    }

    private var placeholderView: some View {
        VStack {
            Image(systemName: "chart.bar")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Panel \(panel.id)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private func captureAndShare() {
        if snapshotImage != nil {
            showShareSheet = true
        }
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Full Screen Panel

struct PanelFullScreenView: View {
    let panel: Panel
    let dashboardUID: String
    let timeRange: TimeRangeOption
    let panels: [Panel]
    let variables: [String: [String]]
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var webAuthManager: WebAuthManager
    @EnvironmentObject var appearanceManager: AppearanceManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var currentIndex: Int
    @State private var showAnnotation = false

    init(panel: Panel, dashboardUID: String, timeRange: TimeRangeOption, panels: [Panel] = [], variables: [String: [String]] = [:]) {
        self.panel = panel
        self.dashboardUID = dashboardUID
        self.timeRange = timeRange
        self.panels = panels
        self.variables = variables
        let idx = panels.firstIndex(where: { $0.id == panel.id }) ?? 0
        _currentIndex = State(initialValue: idx)
    }

    private var currentPanel: Panel {
        panels.isEmpty ? panel : panels[currentIndex]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let client = connectionManager.apiClient {
                    TabView(selection: $currentIndex) {
                        if panels.isEmpty {
                            panelWebView(client: client, panel: panel)
                                .tag(0)
                        } else {
                            ForEach(Array(panels.enumerated()), id: \.element.id) { index, p in
                                panelWebView(client: client, panel: p)
                                    .tag(index)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: panels.count > 1 ? .always : .never))
                } else {
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(currentPanel.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAnnotation = true
                    } label: {
                        Image(systemName: "note.text.badge.plus")
                    }
                }
                if panels.count > 1 {
                    ToolbarItem(placement: .bottomBar) {
                        Text("\(currentIndex + 1) / \(panels.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showAnnotation) {
                CreateAnnotationView(dashboardUID: dashboardUID, panelId: currentPanel.id)
            }
        }
    }

    private func panelWebView(client: GrafanaAPIClient, panel: Panel) -> some View {
        let theme: String = {
            switch appearanceManager.mode {
            case .dark: return "dark"
            case .light: return "light"
            case .system: return colorScheme == .dark ? "dark" : "light"
            }
        }()

        return GrafanaPanelWebView(
            client: client,
            webAuthManager: webAuthManager,
            dashboardUID: dashboardUID,
            panelID: panel.id,
            from: timeRange.rawValue,
            to: "now",
            theme: theme,
            variables: variables,
            onSnapshot: nil
        )
    }
}

// MARK: - Grafana Panel WebView

struct GrafanaPanelWebView: UIViewRepresentable {
    let client: GrafanaAPIClient
    let webAuthManager: WebAuthManager
    let dashboardUID: String
    let panelID: Int
    let from: String
    let to: String
    let theme: String
    var variables: [String: [String]] = [:]
    let onSnapshot: ((UIImage) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = webAuthManager.makeWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        loadPanel(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload when inputs (time range, theme, variable selection) change.
        loadPanel(in: webView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSnapshot: onSnapshot)
    }

    private func loadPanel(in webView: WKWebView, coordinator: Coordinator) {
        Task { @MainActor in
            guard let url = await client.panelEmbedURL(
                dashboardUID: dashboardUID,
                panelID: panelID,
                from: from,
                to: to,
                theme: theme,
                variables: variables
            ) else { return }

            if coordinator.lastLoadedURL == url { return }
            coordinator.lastLoadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onSnapshot: ((UIImage) -> Void)?
        var lastLoadedURL: URL?

        init(onSnapshot: ((UIImage) -> Void)?) {
            self.onSnapshot = onSnapshot
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Capture snapshot after a brief delay for rendering
            guard let onSnapshot = onSnapshot else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                webView.takeSnapshot(with: nil) { image, _ in
                    if let image = image {
                        onSnapshot(image)
                    }
                }
            }
        }
    }
}
