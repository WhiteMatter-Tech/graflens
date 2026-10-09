import SwiftUI
import WebKit

struct PanelCardView: View {
    let panel: Panel
    let dashboardUID: String
    let timeRange: TimeRangeOption
    var refreshID = 0
    var allowsNative = true
    var includeAnnotations = false
    var expanded = false
    var onExpand: (() -> Void)?
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var webAuthManager: WebAuthManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileHeight = 108.0
    @ScaledMetric(relativeTo: .body) private var gaugeTileHeight = 130.0
    @ObservedObject private var model: PanelPresentationModel
    @ObservedObject private var webState: PanelWebState
    @State private var sharedImage: SharedPanelImage?
    @State private var isSharing = false
    @State private var shareError: String?
    @State private var showDetails = false

    private var isGaugeTile: Bool {
        panel.type == "gauge" && allowsNative && !model.forceGrafana && NativePanelConfiguration.supported(panel) != nil
    }
    private var isTile: Bool { (panel.isNumberPanel || isGaugeTile) && !expanded && !typeSize.isAccessibilitySize }
    private var compactHeight: CGFloat { isGaugeTile ? gaugeTileHeight : tileHeight }
    private var isListPreview: Bool { !expanded && ["table", "logs"].contains(panel.type ?? "") }
    private var showsCompactTrend: Bool {
        panel.options["graphMode"]?.string == "area" && Set(model.result?.series.first?.samples.compactMap(\.value) ?? []).count > 1
    }
    private var theme: String { colorScheme == .dark ? "dark" : "light" }
    init(panel: Panel, dashboardUID: String, timeRange: TimeRangeOption,
         refreshID: Int = 0, allowsNative: Bool = true, includeAnnotations: Bool = false,
         expanded: Bool = false, cache: PanelSessionCache, onExpand: (() -> Void)? = nil) {
        self.panel = panel; self.dashboardUID = dashboardUID; self.timeRange = timeRange
        self.refreshID = refreshID; self.allowsNative = allowsNative; self.includeAnnotations = includeAnnotations
        self.expanded = expanded; self.onExpand = onExpand
        let model = cache.model(for: panel.id)
        _model = ObservedObject(wrappedValue: model)
        _webState = ObservedObject(wrappedValue: model.webState)
    }

    private var identity: PanelLoadRequest {
        PanelLoadRequest(connectionID: connectionManager.activeConnection?.id, dashboardUID: dashboardUID,
            panel: panel.document, from: timeRange.rawValue, theme: theme,
            native: allowsNative && !model.forceGrafana, annotations: includeAnnotations,
            refreshID: refreshID, localRefresh: model.localRefresh, sessionRevision: webAuthManager.sessionRevision)
    }
    private var webHeight: CGFloat {
        if expanded { return 600 }
        switch panel.type {
        case "stat", "gauge", "bargauge": return 250
        case "table", "logs": return typeSize.isAccessibilitySize ? 300 : 180
        case "geomap", "heatmap": return 400
        case "timeseries", "graph": return 240
        default: return 320
        }
    }
    private var canShare: Bool { model.result != nil || (model.webURL != nil && webState.loadedAt != nil && !webState.isLoading && webState.error == nil) }

    var body: some View {
        Group {
            if isTile { compactCard } else { regularCard }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
        .task(id: identity) {
            sharedImage = nil
            model.load(identity, client: connectionManager.apiClient)
        }
        .onChange(of: model.result?.loadedAt) { _, date in
            if date != nil { cacheNativeSnapshot() }
        }
        .sheet(item: $sharedImage) { ShareSheetView(items: [$0.image]) }
        .alert("Couldn't share this panel", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK") { shareError = nil }
        } message: { Text(shareError ?? "") }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                Form {
                    Section("Panel") {
                        LabeledContent("Title", value: panel.displayTitle)
                        LabeledContent("Type", value: panel.type ?? "Unknown")
                        LabeledContent("Rendering", value: model.result == nil ? "Grafana" : "Native")
                        LabeledContent("Time range", value: timeRange.label)
                        if let date = model.result?.loadedAt ?? webState.loadedAt {
                            LabeledContent(model.result == nil ? "Page loaded" : "Updated", value: date.formatted())
                        }
                    }
                    if let description = panel.description, !description.isEmpty {
                        Section("Description") { Text(description) }
                    }
                    if let result = model.result {
                        Section("Series") {
                            ForEach(result.series) { series in Text(series.name).font(.callout) }
                        }
                    }
                    if let error = model.error ?? webState.error {
                        Section("Loading error") { Text(error) }
                    }
                    if let reason = model.fallbackReason {
                        Section("Rendering details") { Text(reason).foregroundStyle(.secondary) }
                    }
                }
                .navigationTitle("Panel details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetails = false } } }
            }
        }
    }

    private var panelActions: some View {
        Menu {
            if let onExpand { Button(action: onExpand) { Label("Expand panel", systemImage: "arrow.up.left.and.arrow.down.right") } }
            Button { Task { await share() } } label: { Label("Share image", systemImage: "square.and.arrow.up") }
                .disabled(!canShare || isSharing)
            Button { model.localRefresh += 1 } label: { Label("Refresh panel", systemImage: "arrow.clockwise") }
            if allowsNative && NativePanelConfiguration.supported(panel) != nil {
                Toggle("Use Grafana rendering", isOn: $model.forceGrafana)
            }
            Button { showDetails = true } label: { Label("Panel details", systemImage: "info.circle") }
            Button { openOriginal() } label: { Label("Open in browser", systemImage: "safari") }
        } label: {
            Group {
                if isSharing { ProgressView().controlSize(.small) }
                else { Image(systemName: "ellipsis") }
            }
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Actions for \(panel.displayTitle)")
    }

    private var regularCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.webURL == nil || expanded {
                HStack(alignment: .center, spacing: 4) {
                    if model.webURL == nil {
                        Text(panel.displayTitle).font(.headline).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(timeRange.label).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    panelActions
                    if let onExpand {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Expand \(panel.displayTitle)")
                    }
                }
                .tint(.secondary).padding(.horizontal, 12).padding(.top, 2)
            }

            if let result = model.result, let config = model.configuration {
                nativeContent(result: result, config: config, overview: !expanded && !typeSize.isAccessibilitySize)
            } else if let url = model.webURL {
                ZStack {
                    GrafanaPanelWebView(url: url, requestID: model.requestID, webAuthManager: webAuthManager, state: webState)
                        .id(model.requestID)
                    if webState.isLoading {
                        ProgressView("Loading panel…").padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let error = webState.error {
                        VStack(spacing: 8) {
                            Text(error).font(.callout).multilineTextAlignment(.center).lineLimit(expanded ? nil : 3)
                            Button("Try again") { model.localRefresh += 1 }.buttonStyle(.bordered)
                        }
                        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.secondarySystemGroupedBackground))
                    }
                }
                .frame(height: webHeight)
            } else if let error = model.error {
                ContentUnavailableView("Unable to load panel", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(minHeight: 180)
            } else {
                ProgressView("Loading readings…").frame(maxWidth: .infinity, minHeight: 180)
            }

            if model.webURL != nil && !expanded {
                HStack {
                    if let onExpand {
                        Button(action: onExpand) {
                            Label(isListPreview ? (panel.type == "logs" ? "View logs" : "View all rows") : "Expand panel",
                                  systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.medium)).frame(minHeight: 44)
                        }
                    }
                    Spacer(minLength: 0)
                    panelActions
                }
                .padding(.leading, 12).padding(.trailing, 4).tint(.secondary)
            }
            if expanded {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption2)
                    if let date = model.result?.loadedAt ?? webState.loadedAt {
                        Text("\(model.result == nil ? "Page loaded" : "Updated") \(date.formatted(date: .omitted, time: .shortened))")
                    } else { Text("Waiting for panel") }
                    Spacer()
                    Text(timeRange.label)
                }
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }

    private var compactCard: some View {
        ZStack {
            if let url = model.webURL {
                GeometryReader { geometry in
                    // Fit the complete Grafana viewport; preserve plugin formatting,
                    // value mappings, and threshold colors instead of scraping values.
                    GrafanaPanelWebView(url: url, requestID: model.requestID,
                        webAuthManager: webAuthManager, state: webState)
                        .id(model.requestID)
                        .frame(width: geometry.size.width / 0.7, height: geometry.size.height / 0.7)
                        .scaleEffect(0.7, anchor: .topLeading)
                }
                .clipped().allowsHitTesting(false).accessibilityHidden(true)
                if webState.isLoading { ProgressView().accessibilityLabel("Loading \(panel.displayTitle)") }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(panel.displayTitle).font(.subheadline.weight(.medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.leading, 12).padding(.trailing, 40)
                    if let result = model.result, let config = model.configuration {
                        Group {
                            if config.kind == "gauge" {
                                NativeGaugePanel(result: result, configuration: config, compact: true)
                            } else {
                                NativeStatPanel(result: result, configuration: config, compact: true, showsTrend: showsCompactTrend)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Loading \(panel.displayTitle)")
                    }
                }
                if let result = model.result, let config = model.configuration {
                    let value = config.reducer == "last" ? result.series.first?.samples.last?.value : result.series.first?.latest
                    HStack { Capsule().fill(ChartPalette.thresholdColor(value, configuration: config)).frame(width: 3, height: 24); Spacer() }
                        .padding(.leading, 1).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            if model.error != nil || webState.error != nil {
                compactFailure
            } else if let onExpand {
                Button(action: onExpand) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand \(panel.displayTitle)")
                    .accessibilityValue(compactAccessibilityValue)
            }
        }
        .frame(height: compactHeight)
        .overlay(alignment: model.webURL == nil ? .topTrailing : .bottomTrailing) {
            panelActions
                .background {
                    if model.webURL != nil {
                        Circle().fill(.regularMaterial).frame(width: 28, height: 28)
                    }
                }
                .tint(.secondary)
        }
    }

    private var compactAccessibilityValue: String {
        guard let result = model.result, let config = model.configuration else { return "Grafana panel. Open to inspect readings." }
        let value = config.reducer == "last" ? result.series.first?.samples.last?.value : result.series.first?.latest
        return MetricFormat.string(value, unit: config.unit, decimals: config.decimals)
    }

    private var compactFailure: some View {
        VStack(spacing: 4) {
            Text("Unable to load").font(.caption).foregroundStyle(.secondary)
            Button("Try again") { model.localRefresh += 1 }
                .font(.caption).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder private func nativeContent(result: NativePanelResult, config: NativePanelConfiguration, overview: Bool = false) -> some View {
        switch config.kind {
        case "stat": NativeStatPanel(result: result, configuration: config)
        case "gauge": NativeGaugePanel(result: result, configuration: config)
        default: NativeTimeSeriesPanel(title: panel.displayTitle, result: result, configuration: config, compact: overview, onExpand: onExpand)
        }
    }

    @MainActor private func share() async {
        guard !isSharing, let connectionID = connectionManager.activeConnection?.id else { return }
        let requestIdentity = identity
        isSharing = true
        defer { isSharing = false }
        do {
            let image: UIImage
            if let result = model.result, let config = model.configuration {
                let content = VStack(alignment: .leading, spacing: 0) {
                    Text(panel.displayTitle).font(.title3.bold()).padding(20)
                    nativeContent(result: result, config: config)
                    Text("\(timeRange.label) · \(result.loadedAt.formatted())").font(.caption).foregroundStyle(.secondary).padding(20)
                }
                .frame(width: 700).background(Color(.systemBackground)).environment(\.colorScheme, colorScheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let rendered = renderer.uiImage else { throw GrafanaAPIError.invalidResponse }
                image = rendered
            } else {
                image = try await webState.snapshot()
            }
            guard requestIdentity == identity, !Task.isCancelled else { return }
            if let data = image.jpegData(compressionQuality: 0.9) {
                SharedDataManager.savePanelSnapshot(connectionID: connectionID, dashboardUID: dashboardUID, panelID: panel.id,
                    from: timeRange.rawValue, theme: theme, imageData: data)
            }
            sharedImage = SharedPanelImage(image: image)
        } catch { shareError = "Wait for the panel to finish loading, then try again. \(error.localizedDescription)" }
    }

    @MainActor private func cacheNativeSnapshot() {
        guard let result = model.result, let config = model.configuration,
              let connectionID = connectionManager.activeConnection?.id else { return }
        let content = VStack(alignment: .leading, spacing: 0) {
            Text(panel.displayTitle).font(.headline).padding(16)
            nativeContent(result: result, config: config)
        }
        .frame(width: 500).background(Color(.systemBackground)).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.85) else { return }
        SharedDataManager.savePanelSnapshot(connectionID: connectionID, dashboardUID: dashboardUID,
            panelID: panel.id, from: timeRange.rawValue, theme: "dark", imageData: data)
    }

    private func openOriginal() {
        Task {
            guard let url = await connectionManager.apiClient?.panelEmbedURL(dashboardUID: dashboardUID, panelID: panel.id, from: timeRange.rawValue, theme: theme) else { return }
            await UIApplication.shared.open(url)
        }
    }
}

struct SharedPanelImage: Identifiable { let id = UUID(); let image: UIImage }
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct PanelFullScreenView: View {
    let panel: Panel
    let dashboardUID: String
    let panels: [Panel]
    let allowsNative: Bool
    let includeAnnotations: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var timeRange: TimeRangeOption
    @State private var currentIndex: Int
    // A separate surface must never reparent the dashboard's live WKWebView.
    @StateObject private var panelCache = PanelSessionCache()
    @State private var refreshID = 0
    @State private var showAnnotation = false
    init(panel: Panel, dashboardUID: String, timeRange: TimeRangeOption, panels: [Panel] = [], allowsNative: Bool = true, includeAnnotations: Bool = false) {
        self.panel = panel; self.dashboardUID = dashboardUID; self.panels = panels; self.allowsNative = allowsNative; self.includeAnnotations = includeAnnotations
        _timeRange = State(initialValue: timeRange)
        _currentIndex = State(initialValue: panels.firstIndex(where: { $0.id == panel.id }) ?? 0)
    }
    private var currentPanel: Panel { panels.isEmpty ? panel : panels[currentIndex] }
    var body: some View {
        NavigationStack {
            ScrollView {
                PanelCardView(panel: currentPanel, dashboardUID: dashboardUID, timeRange: timeRange, refreshID: refreshID, allowsNative: allowsNative, includeAnnotations: includeAnnotations, expanded: true, cache: panelCache)
                    .id(currentPanel.id).padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(currentPanel.displayTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { TimeRangeMenu(selection: $timeRange) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { refreshID += 1 } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        Button { showAnnotation = true } label: { Label("Add annotation", systemImage: "note.text.badge.plus") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Panel actions")
                }
                if panels.count > 1 {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { currentIndex -= 1 } label: { Label("Previous", systemImage: "chevron.left") }.disabled(currentIndex == 0)
                        Spacer()
                        Text("\(currentIndex + 1) of \(panels.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button { currentIndex += 1 } label: { Label("Next", systemImage: "chevron.right") }.disabled(currentIndex == panels.count - 1)
                    }
                }
            }
            .sheet(isPresented: $showAnnotation) { CreateAnnotationView(dashboardUID: dashboardUID, panelId: currentPanel.id) }
        }
    }
}
