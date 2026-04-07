import SwiftUI

struct NativeGaugePanel: View {
    let title: String
    let value: Double
    let min: Double
    let max: Double
    let unit: String?
    let thresholds: [ThresholdStep]

    init(title: String, value: Double, min: Double = 0, max: Double = 100, unit: String? = "%", thresholds: [ThresholdStep] = []) {
        self.title = title
        self.value = value
        self.min = min
        self.max = max
        self.unit = unit
        self.thresholds = thresholds.isEmpty ? Self.defaultThresholds : thresholds
    }

    static let defaultThresholds: [ThresholdStep] = [
        ThresholdStep(value: 0, color: .green),
        ThresholdStep(value: 70, color: .orange),
        ThresholdStep(value: 90, color: .red),
    ]

    private var normalizedValue: Double {
        guard max > min else { return 0 }
        return Swift.min(Swift.max((value - min) / (max - min), 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background arc
                ArcShape(startAngle: .degrees(-210), endAngle: .degrees(30))
                    .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 14, lineCap: .round))

                // Value arc
                ArcShape(
                    startAngle: .degrees(-210),
                    endAngle: .degrees(-210 + normalizedValue * 240)
                )
                .stroke(currentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))

                // Value text
                VStack(spacing: 2) {
                    Text(formattedValue)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(currentColor)

                    if let unit = unit {
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 120)
            .padding(.horizontal, 20)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var formattedValue: String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private var currentColor: Color {
        guard !thresholds.isEmpty else { return .orange }
        let sorted = thresholds.sorted { ($0.value ?? -.infinity) < ($1.value ?? -.infinity) }
        var color: Color = .green
        for step in sorted {
            if let threshold = step.value, value >= threshold {
                color = step.color
            }
        }
        return color
    }
}

// MARK: - Arc Shape

struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY + 10)
        let radius = min(rect.width, rect.height) / 2 - 10
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}
