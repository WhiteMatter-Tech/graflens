import SwiftUI

struct NativeGaugePanel: View {
    let result: NativePanelResult
    let configuration: NativePanelConfiguration
    var compact = false
    private var value: Double? {
        configuration.reducer == "last" ? result.series.first?.samples.last?.value : result.series.first?.latest
    }
    private var fraction: Double {
        guard let value, let min = configuration.minimum, let max = configuration.maximum, max > min else { return 0 }
        return Swift.min(Swift.max((value - min) / (max - min), 0), 1)
    }
    var body: some View {
        if compact { compactGauge } else { dial }
    }

    private var compactGauge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MetricFormat.string(value, unit: configuration.unit, decimals: configuration.decimals))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(ChartPalette.thresholdColor(value, configuration: configuration))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.12))
                    if value != nil {
                        Capsule().fill(ChartPalette.thresholdColor(value, configuration: configuration))
                            .frame(width: geometry.size.width * fraction)
                    }
                }
            }
            .frame(height: 6)
            HStack {
                Text(MetricFormat.string(configuration.minimum, unit: configuration.unit))
                Spacer(minLength: 4)
                Text(MetricFormat.string(configuration.maximum, unit: configuration.unit))
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MetricFormat.string(value, unit: configuration.unit, decimals: configuration.decimals)), range \(MetricFormat.string(configuration.minimum, unit: configuration.unit)) to \(MetricFormat.string(configuration.maximum, unit: configuration.unit))")
    }

    private var dial: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(.secondary.opacity(0.12), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                Circle().trim(from: 0, to: 0.75 * fraction)
                    .stroke(ChartPalette.thresholdColor(value, configuration: configuration), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                VStack(spacing: 5) {
                    Text(MetricFormat.string(value, unit: configuration.unit, decimals: configuration.decimals))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text("Latest reading").font(.caption).foregroundStyle(.secondary)
                }
                .rotationEffect(.degrees(-135)).padding(24)
            }
            .rotationEffect(.degrees(135))
            .frame(width: 150, height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gauge, \(MetricFormat.string(value, unit: configuration.unit, decimals: configuration.decimals))")
            HStack {
                Text(MetricFormat.string(configuration.minimum, unit: configuration.unit))
                Spacer()
                Text(MetricFormat.string(configuration.maximum, unit: configuration.unit))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: .infinity)
    }
}
