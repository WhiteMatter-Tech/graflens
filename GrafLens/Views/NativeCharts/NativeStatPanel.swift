import SwiftUI
import Charts

struct NativeStatPanel: View {
    let result: NativePanelResult
    let configuration: NativePanelConfiguration
    var compact = false
    var showsTrend = true
    private var series: NativeSeries? { result.series.first }
    private var value: Double? { configuration.reducer == "last" ? series?.samples.last?.value : series?.latest }
    private var color: Color { ChartPalette.thresholdColor(value, configuration: configuration) }

    private var domain: ClosedRange<Double> {
        let values = series?.samples.compactMap(\.value) ?? []
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max((high - low) * 0.15, max(abs(high) * 0.02, 0.1))
        let lower = configuration.minimum ?? (low - padding)
        return lower...max(configuration.maximum ?? (high + padding), lower + max(abs(lower) * 0.01, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 18) {
            Text(MetricFormat.string(value, unit: configuration.unit, decimals: configuration.decimals))
                .font(.system(size: compact ? 32 : 42, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityLabel("Latest reading, \(MetricFormat.string(value, unit: configuration.unit, decimals: configuration.decimals))")
            if showsTrend, let series, !series.samples.isEmpty, !compact || value != nil {
                Chart {
                    ForEach(Array(series.segments.enumerated()), id: \.offset) { index, samples in
                        ForEach(samples) { point in
                            if let v = point.value {
                                LineMark(x: .value("Time", point.timestamp), y: .value("Value", v), series: .value("Segment", index))
                                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            }
                        }
                    }
                }
                .chartYScale(domain: domain)
                .chartPlotStyle { $0.clipped() }
                .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
                .chartXScale(domain: result.from...result.to)
                .frame(height: compact ? 16 : 60)
                .accessibilityLabel("Trend over the selected time range")
            }
            if !compact || value == nil {
                Text(value == nil ? "No reading in this range" : "Latest reading")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 12 : 20).padding(.vertical, compact ? 2 : 20)
    }
}
