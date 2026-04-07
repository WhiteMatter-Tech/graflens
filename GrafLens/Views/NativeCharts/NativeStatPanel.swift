import SwiftUI
import Charts

struct NativeStatPanel: View {
    let title: String
    let value: Double?
    let unit: String?
    let sparklineData: [Double]
    let thresholds: [ThresholdStep]

    init(title: String, value: Double? = nil, unit: String? = nil, sparklineData: [Double] = [], thresholds: [ThresholdStep] = []) {
        self.title = title
        self.value = value
        self.unit = unit
        self.sparklineData = sparklineData
        self.thresholds = thresholds
    }

    var body: some View {
        VStack(spacing: 8) {
            if let value = value {
                Text(formattedValue(value))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(colorForValue(value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            if !sparklineData.isEmpty {
                Chart {
                    ForEach(Array(sparklineData.enumerated()), id: \.offset) { index, val in
                        AreaMark(
                            x: .value("Time", index),
                            y: .value("Value", val)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [colorForValue(value ?? val).opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", index),
                            y: .value("Value", val)
                        )
                        .foregroundStyle(colorForValue(value ?? val))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 40)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private func formattedValue(_ val: Double) -> String {
        let suffix = unit ?? ""
        if val >= 1_000_000_000 {
            return String(format: "%.1fG%@", val / 1_000_000_000, suffix)
        } else if val >= 1_000_000 {
            return String(format: "%.1fM%@", val / 1_000_000, suffix)
        } else if val >= 1_000 {
            return String(format: "%.1fK%@", val / 1_000, suffix)
        } else if val == val.rounded() {
            return "\(Int(val))\(suffix)"
        } else {
            return String(format: "%.2f%@", val, suffix)
        }
    }

    private func colorForValue(_ val: Double) -> Color {
        guard !thresholds.isEmpty else { return .orange }
        let sorted = thresholds.sorted { ($0.value ?? -.infinity) < ($1.value ?? -.infinity) }
        var color: Color = .green
        for step in sorted {
            if let threshold = step.value, val >= threshold {
                color = step.color
            }
        }
        return color
    }
}

struct ThresholdStep {
    let value: Double?
    let color: Color
}
