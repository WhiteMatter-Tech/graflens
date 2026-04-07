import SwiftUI
import Charts

struct NativeBarChartPanel: View {
    let title: String
    let bars: [BarData]
    let horizontal: Bool

    init(title: String, bars: [BarData], horizontal: Bool = false) {
        self.title = title
        self.bars = bars
        self.horizontal = horizontal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bars.isEmpty {
                noDataView
            } else {
                Chart(bars) { bar in
                    if horizontal {
                        BarMark(
                            x: .value("Value", bar.value),
                            y: .value("Category", bar.label)
                        )
                        .foregroundStyle(bar.color ?? .orange)
                        .cornerRadius(4)
                    } else {
                        BarMark(
                            x: .value("Category", bar.label),
                            y: .value("Value", bar.value)
                        )
                        .foregroundStyle(bar.color ?? .orange)
                        .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var noDataView: some View {
        VStack {
            Image(systemName: "chart.bar")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BarData: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color?

    init(label: String, value: Double, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }
}
