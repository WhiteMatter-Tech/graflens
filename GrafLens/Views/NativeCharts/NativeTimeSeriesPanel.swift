import SwiftUI
import Charts

struct NativeTimeSeriesPanel: View {
    let title: String
    let series: [TimeSeriesData]

    @State private var selectedPoint: (seriesIndex: Int, dataIndex: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if series.isEmpty {
                noDataView
            } else {
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { seriesIdx, s in
                        ForEach(Array(s.points.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(by: .value("Series", s.name))
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(by: .value("Series", s.name))
                            .opacity(0.1)
                        }
                    }
                }
                .chartForegroundStyleScale(range: chartColors)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartLegend(series.count > 1 ? .visible : .hidden)
                .chartLegend(position: .bottom, spacing: 4)

                // Legend for single series
                if series.count == 1 {
                    HStack {
                        Text(series[0].name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let last = series[0].points.last {
                            Text(formatValue(last.value))
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var noDataView: some View {
        VStack {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartColors: [Color] {
        [.orange, .blue, .green, .purple, .pink, .cyan, .yellow, .red, .mint, .indigo]
    }

    private func formatValue(_ val: Double) -> String {
        if val >= 1_000_000 { return String(format: "%.1fM", val / 1_000_000) }
        if val >= 1_000 { return String(format: "%.1fK", val / 1_000) }
        if val == val.rounded() { return "\(Int(val))" }
        return String(format: "%.2f", val)
    }
}

// MARK: - Data Models

struct TimeSeriesData: Identifiable {
    let id = UUID()
    let name: String
    let points: [TimeSeriesPoint]
}

struct TimeSeriesPoint {
    let timestamp: Date
    let value: Double
}
