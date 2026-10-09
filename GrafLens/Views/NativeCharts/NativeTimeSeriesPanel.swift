import SwiftUI
import Charts

struct NativeTimeSeriesPanel: View {
    let title: String
    let result: NativePanelResult
    let configuration: NativePanelConfiguration
    var compact = false
    var onExpand: (() -> Void)?
    @State private var selectedDate: Date?
    @State private var hiddenSeries: Set<String> = []
    @State private var showInspector = false

    private var series: [NativeSeries] { result.series }
    private var domain: ClosedRange<Double> {
        let values = series.flatMap(\.samples).compactMap(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max((high - low) * 0.12, max(abs(high) * 0.02, 0.1))
        let lower = configuration.minimum ?? (low - padding)
        let upper = configuration.maximum ?? (high + padding)
        return lower...max(upper, lower + max(abs(lower) * 0.01, 1))
    }
    private func pattern(_ s: NativeSeries) -> Int { (series.sorted { $0.id < $1.id }.firstIndex(where: { $0.id == s.id }) ?? 0) % 2 }
    private func color(_ series: NativeSeries) -> Color { ChartPalette.color(for: series.id, fixed: configuration.fixedColor) }
    private func reading(_ series: NativeSeries) -> Double? {
        guard let selectedDate else { return series.latest }
        return series.samples.min(by: { abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate)) })?.value
    }
    private func formatted(_ value: Double?) -> String { MetricFormat.string(value, unit: configuration.unit, decimals: configuration.decimals) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 16) {
            if series.allSatisfy({ $0.samples.allSatisfy { $0.value == nil } }) {
                ContentUnavailableView("No readings", systemImage: "chart.xyaxis.line", description: Text("No data in the selected time range."))
            } else {
                if series.count == 1, let first = series.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatted(reading(first)))
                            .font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit().contentTransition(.numericText())
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(selectedDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Latest reading")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                chart
                    .frame(height: compact ? 200 : 260)
                VStack(spacing: 4) {
                    ForEach(compact ? Array(series.prefix(2)) : series) { s in
                        Button {
                            if hiddenSeries.contains(s.id) { hiddenSeries.remove(s.id) }
                            else if hiddenSeries.count < series.count - 1 { hiddenSeries.insert(s.id) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(pattern(s) == 0 ? "━" : "┄")
                                    .foregroundStyle(color(s)).font(.body.bold()).accessibilityHidden(true)
                                Text(s.name).font(.caption).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text(formatted(reading(s))).font(.caption.monospacedDigit().weight(.medium))
                            }
                            .foregroundStyle(.primary)
                            .opacity(hiddenSeries.contains(s.id) ? 0.4 : 1)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(s.name), \(formatted(reading(s)))")
                        .accessibilityValue(hiddenSeries.contains(s.id) ? "Hidden" : "Visible")
                        .accessibilityHint("Toggle this series. At least one series remains visible.")
                    }
                }
                if compact, series.count > 2, let onExpand {
                    Button("View all \(series.count) series", action: onExpand)
                        .font(.caption).frame(minHeight: 44)
                }
                if compact, !result.annotations.isEmpty {
                    Label("\(result.annotations.count) annotations", systemImage: "text.bubble")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !compact && !result.annotations.isEmpty {
                    DisclosureGroup("\(result.annotations.count) annotations") {
                        ForEach(result.annotations) { annotation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Date(timeIntervalSince1970: Double(annotation.time) / 1000).formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(annotation.text).font(.caption).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                    }
                    .font(.caption).tint(.secondary)
                }
                if !compact {
                    DisclosureGroup("Inspect readings", isExpanded: $showInspector) {
                        let times = Array(Set(series.flatMap(\.samples).map(\.timestamp))).sorted()
                        if times.count > 1 {
                            Slider(value: Binding(get: {
                                Double(times.firstIndex(where: { $0 >= (selectedDate ?? times.last!) }) ?? times.count - 1)
                            }, set: { selectedDate = times[Int($0)] }), in: 0...Double(times.count - 1), step: 1)
                            .accessibilityLabel("Reading time")
                            .accessibilityValue((selectedDate ?? times.last!).formatted(date: .abbreviated, time: .shortened))
                            HStack {
                                Text((selectedDate ?? times.last!).formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Latest") { selectedDate = nil }
                                    .font(.caption).frame(minHeight: 44)
                            }
                        }
                    }
                    .font(.caption).tint(.secondary)
                }
            }
        }
        .padding(compact ? 12 : 20)
    }

    private var chart: some View {
        Chart {
            ForEach(result.annotations) { annotation in
                let start = Date(timeIntervalSince1970: Double(annotation.time) / 1000)
                if let end = annotation.timeEnd, end > annotation.time {
                    RectangleMark(xStart: .value("Start", start), xEnd: .value("End", Date(timeIntervalSince1970: Double(end) / 1000)), yStart: .value("Min", domain.lowerBound), yEnd: .value("Max", domain.upperBound))
                        .foregroundStyle(.teal.opacity(0.08))
                }
                RuleMark(x: .value("Annotation", start))
                    .foregroundStyle(.teal.opacity(0.65)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .accessibilityLabel(annotation.text)
            }
            ForEach(series.filter { !hiddenSeries.contains($0.id) }) { s in
                ForEach(Array(s.segments.enumerated()), id: \.offset) { segmentIndex, samples in
                    ForEach(samples) { sample in
                        if let value = sample.value {
                            if series.count == 1 {
                                AreaMark(x: .value("Time", sample.timestamp), yStart: .value("Baseline", domain.lowerBound), yEnd: .value("Value", value), series: .value("Segment", "\(s.id)-\(segmentIndex)"))
                                    .foregroundStyle(LinearGradient(colors: [color(s).opacity(0.16), color(s).opacity(0.01)], startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.linear)
                            }
                            LineMark(x: .value("Time", sample.timestamp), y: .value("Value", value), series: .value("Segment", "\(s.id)-\(segmentIndex)"))
                                .foregroundStyle(color(s))
                                .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round, dash: pattern(s) == 0 ? [] : [6, 4]))
                                .interpolationMethod(.linear)
                            if samples.count == 1 {
                                PointMark(x: .value("Time", sample.timestamp), y: .value("Value", value))
                                    .foregroundStyle(color(s)).symbolSize(24)
                            }
                        }
                    }
                }
            }
            if let selectedDate {
                RuleMark(x: .value("Selected time", selectedDate))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ForEach(series.filter { !hiddenSeries.contains($0.id) }) { s in
                    if let sample = s.samples.min(by: { abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate)) }), let value = sample.value {
                        PointMark(x: .value("Time", sample.timestamp), y: .value("Value", value))
                            .foregroundStyle(color(s)).symbolSize(40)
                    }
                }
            }
        }
        .chartXScale(domain: result.from...result.to)
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in plot.clipped() }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: result.to.timeIntervalSince(result.from) > 86400 ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute())
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let n = value.as(Double.self) { Text(formatted(n)).font(.caption2) }
                }
            }
        }
        .accessibilityLabel("\(title), \(series.count) series")
        .accessibilityHint(compact ? "Expand the panel to inspect individual readings and all series." : "Use Inspect readings below for individual values.")
    }
}

enum ChartPalette {
    static let colors: [Color] = [.orange, .teal, .indigo, .pink, .blue, .purple]
    static func hash(_ id: String) -> Int { id.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff } }
    static func pattern(for id: String) -> Int { hash(id) % 2 }
    static func color(for id: String, fixed: String? = nil) -> Color { fixed.map(resolve) ?? colors[hash(id) % colors.count] }
    static func resolve(_ value: String) -> Color {
        switch value.lowercased() {
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        case "orange": return .orange
        case "blue": return .blue
        case "purple": return .purple
        case "cyan", "teal": return .teal
        default:
            let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if hex.count == 6, let n = UInt64(hex, radix: 16) {
                return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
            }
            return .orange
        }
    }
    static func thresholdColor(_ value: Double?, configuration: NativePanelConfiguration) -> Color {
        if let fixed = configuration.fixedColor { return resolve(fixed) }
        guard let value else { return .secondary }
        var color: Color = .orange
        for step in configuration.thresholds.sorted(by: { ($0.value ?? -.infinity) < ($1.value ?? -.infinity) }) {
            if step.value == nil || value >= step.value! { color = resolve(step.color) }
        }
        return color
    }
}
