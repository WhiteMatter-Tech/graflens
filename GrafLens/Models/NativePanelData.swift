import Foundation

/// Native rendering is opt-in by capability, with the original panel always available.
struct NativePanelConfiguration {
    let kind: String
    let unit: String
    let decimals: Int?
    let minimum: Double?
    let maximum: Double?
    let reducer: String
    let fixedColor: String?
    let thresholds: [NativeThreshold]

    static func supported(_ panel: Panel) -> NativePanelConfiguration? {
        guard let kind = panel.type, ["timeseries", "stat", "gauge"].contains(kind),
              (panel.document["transformations"]?.array ?? []).isEmpty,
              (panel.document["fieldConfig"]?["overrides"]?.array ?? []).isEmpty,
              panel.document["timeFrom"]?.string?.isEmpty != false,
              panel.document["timeShift"]?.string?.isEmpty != false,
              panel.document["repeat"]?.string?.isEmpty != false else { return nil }
        // A panel may reference dashboard variables outside the query (titles, units, etc.).
        guard !JSONValue.object(panel.document).containsVariable else { return nil }
        let f = panel.fieldDefaults
        let custom = f["custom"]?.object ?? [:]
        guard (f["mappings"]?.array ?? []).isEmpty,
              f["displayName"]?.string == nil,
              f["links"]?.array?.isEmpty != false,
              custom["scaleDistribution"]?["type"]?.string ?? "linear" == "linear",
              custom["stacking"]?["mode"]?.string ?? "none" == "none",
              custom["axisPlacement"]?.string ?? "auto" != "right",
              custom["axisPlacement"]?.string ?? "auto" != "hidden",
              custom["drawStyle"]?.string ?? "line" == "line",
              custom["lineInterpolation"]?.string ?? "linear" == "linear",
              custom["spanNulls"] == nil || custom["spanNulls"] == .bool(false),
              custom["insertNulls"] == nil || custom["insertNulls"] == .bool(false),
              custom["axisSoftMin"]?.double == nil, custom["axisSoftMax"]?.double == nil,
              custom["hideFrom"]?["viz"]?.bool != true,
              custom["axisCenteredZero"]?.bool != true,
              custom["transform"]?.string == nil || custom["transform"]?.string == "none",
              custom["fillBelowTo"]?.string?.isEmpty != false,
              custom["axisLabel"]?.string?.isEmpty != false,
              custom["thresholdsStyle"]?["mode"]?.string ?? "off" == "off" else { return nil }
        let unit = f["unit"]?.string ?? "none"
        guard MetricFormat.supportedUnits.contains(unit) else { return nil }
        let min = f["min"]?.double, max = f["max"]?.double
        guard min == nil || (min!.isFinite && abs(min!) < 1e100), max == nil || (max!.isFinite && abs(max!) < 1e100),
              min == nil || max == nil || min! < max! else { return nil }
        let colorMode = f["color"]?["mode"]?.string ?? (kind == "timeseries" ? "palette-classic" : "thresholds")
        guard (kind == "timeseries" ? ["palette-classic", "fixed"] : ["thresholds", "fixed"]).contains(colorMode) else { return nil }
        guard f["thresholds"]?["mode"]?.string ?? "absolute" == "absolute" else { return nil }
        let thresholdSteps = f["thresholds"]?["steps"]?.array ?? []
        let fixedColor = colorMode == "fixed" ? f["color"]?["fixedColor"]?.string : nil
        if colorMode == "fixed" && (fixedColor == nil || !supportsColor(fixedColor!)) { return nil }
        guard thresholdSteps.allSatisfy({ supportsColor($0["color"]?.string ?? "green") }) else { return nil }
        let reducer = panel.options["reduceOptions"]?["calcs"]?.array?.first?.string ?? "lastNotNull"
        if kind != "timeseries" {
            guard ["lastNotNull", "last"].contains(reducer),
                  (panel.options["reduceOptions"]?["calcs"]?.array?.count ?? 1) <= 1,
                  panel.options["reduceOptions"]?["values"]?.bool != true,
                  panel.options["reduceOptions"]?["fields"]?.string?.isEmpty != false,
                  panel.options["textMode"]?.string ?? "auto" != "name" else { return nil }
        }
        // Gauge autoscaling and per-field ranges differ across Grafana versions.
        guard kind != "gauge" || (min != nil && max != nil) else { return nil }
        return NativePanelConfiguration(kind: kind, unit: unit, decimals: f["decimals"]?.int.map { Swift.min(Swift.max($0, 0), 12) }, minimum: min, maximum: max, reducer: reducer,
            fixedColor: colorMode == "fixed" ? f["color"]?["fixedColor"]?.string : nil,
            thresholds: (f["thresholds"]?["steps"]?.array ?? []).map { NativeThreshold(value: $0["value"]?.double, color: $0["color"]?.string ?? "green") })
    }
    static func supportsColor(_ value: String) -> Bool {
        if ["green", "red", "yellow", "orange", "blue", "purple", "cyan", "teal"].contains(value.lowercased()) { return true }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return hex.count == 6 && UInt64(hex, radix: 16) != nil
    }
}

struct NativeThreshold { let value: Double?; let color: String }

struct NativeSample: Identifiable {
    let timestamp: Date
    let value: Double?
    var id: Date { timestamp }
}

struct NativeSeries: Identifiable {
    let id: String
    let name: String
    let samples: [NativeSample]
    var latest: Double? { samples.last(where: { $0.value != nil })?.value }

    /// A missing sample splits the path. It must never become a zero or a bridge.
    var segments: [[NativeSample]] {
        var result: [[NativeSample]] = []
        var run: [NativeSample] = []
        for sample in samples {
            if sample.value != nil { run.append(sample) }
            else if !run.isEmpty { result.append(run); run = [] }
        }
        if !run.isEmpty { result.append(run) }
        return result
    }
}

struct NativePanelResult {
    let series: [NativeSeries]
    let from: Date
    let to: Date
    let loadedAt: Date
    var annotations: [GrafanaAnnotation] = []
}

enum NativePanelError: LocalizedError {
    case unsupported, invalidFrames, queryFailed(String)
    var errorDescription: String? {
        switch self {
        case .unsupported: return "This panel uses Grafana rendering to preserve its configuration."
        case .invalidFrames: return "The data cannot be displayed faithfully as a native chart."
        case .queryFailed(let message): return message
        }
    }
}

enum NativeFrameDecoder {
    static func decode(_ response: JSONValue, targets: [[String: JSONValue]]) throws -> [NativeSeries] {
        guard let results = response["results"]?.object else { throw NativePanelError.invalidFrames }
        var series: [NativeSeries] = []
        for target in targets {
            let ref = target["refId"]?.string ?? "A"
            guard let result = results[ref] else { throw NativePanelError.invalidFrames }
            if let error = result["error"]?.string { throw NativePanelError.queryFailed(error) }
            if let status = result["status"]?.int, status >= 400 { throw NativePanelError.queryFailed("Query \(ref) failed (\(status)).") }
            guard let frames = result["frames"]?.array else { throw NativePanelError.invalidFrames }
            for frame in frames {
                guard let fields = frame["schema"]?["fields"]?.array,
                      let columns = frame["data"]?["values"]?.array,
                      columns.count == fields.count else { throw NativePanelError.invalidFrames }
                if columns.allSatisfy({ $0.array?.isEmpty == true }) { continue }
                guard fields.contains(where: { $0["type"]?.string == "number" }) else { throw NativePanelError.invalidFrames }
                guard let timeIndex = fields.firstIndex(where: { $0["type"]?.string == "time" }),
                      let timestamps = columns[timeIndex].array else { throw NativePanelError.invalidFrames }
                for (fieldIndex, field) in fields.enumerated() where field["type"]?.string == "number" {
                    guard let values = columns[fieldIndex].array, values.count == timestamps.count else { throw NativePanelError.invalidFrames }
                    let labels = field["labels"]?.object ?? [:]
                    let labelText = labels.keys.sorted().map { "\($0)=\(labels[$0]?.string ?? "")" }.joined(separator: ", ")
                    let base = field["config"]?["displayNameFromDS"]?.string ?? field["name"]?.string ?? ref
                    var name = labelText.isEmpty || field["config"]?["displayNameFromDS"]?.string != nil ? base : "\(base) {\(labelText)}"
                    if let template = target["legendFormat"]?.string, !template.isEmpty, template != "__auto" {
                        name = template
                        for (key, value) in labels { name = name.replacingOccurrences(of: "{{\(key)}}", with: value.string ?? "") }
                        if name.contains("{{") { throw NativePanelError.unsupported }
                    }
                    var samples: [NativeSample] = []
                    for (time, value) in zip(timestamps, values) {
                        guard let ms = time.double, ms.isFinite, abs(ms) < 8.64e15 else { throw NativePanelError.invalidFrames }
                        guard value == .null || value.double != nil else { throw NativePanelError.invalidFrames }
                        let n = value.double.flatMap { $0.isFinite ? $0 : nil }
                        if let n, abs(n) > 1e100 { throw NativePanelError.unsupported }
                        samples.append(NativeSample(timestamp: Date(timeIntervalSince1970: ms / 1000), value: n))
                    }
                    samples.sort { $0.timestamp < $1.timestamp }
                    guard Set(samples.map(\.timestamp)).count == samples.count else { throw NativePanelError.invalidFrames }
                    let id = "\(ref)|\(base)|\(labelText)"
                    guard !series.contains(where: { $0.id == id }) else { throw NativePanelError.invalidFrames }
                    series.append(NativeSeries(id: id, name: name, samples: samples))
                }
            }
        }
        return series
    }
}

enum MetricFormat {
    static let supportedUnits: Set<String> = ["none", "short", "", "percent", "percentunit", "ms", "s", "bytes", "decbytes", "bps", "Bps", "hertz", "celsius", "fahrenheit"]
    static func string(_ value: Double?, unit: String = "none", decimals: Int? = nil) -> String {
        guard let value, value.isFinite else { return "—" }
        var n = value
        var suffix = ""
        switch unit {
        case "percent": suffix = "%"
        case "percentunit": n *= 100; suffix = "%"
        case "celsius": suffix = " °C"
        case "fahrenheit": suffix = " °F"
        case "ms": suffix = " ms"
        case "s": suffix = " s"
        case "hertz": suffix = " Hz"
        case "bytes", "decbytes", "bps", "Bps", "short":
            let base = unit == "bytes" ? 1024.0 : 1000.0
            let prefixes = unit == "bytes" ? ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei"] : ["", "k", "M", "G", "T", "P", "E"]
            var i = 0
            while abs(n) >= base && i < prefixes.count - 1 { n /= base; i += 1 }
            let end = ["bytes": "B", "decbytes": "B", "bps": "bit/s", "Bps": "B/s", "short": ""][unit] ?? ""
            suffix = (end.isEmpty && i == 0 ? "" : " ") + prefixes[i] + end
        default: break
        }
        guard n.isFinite else { return "—" }
        let digits = decimals ?? (abs(n) >= 100 || n == n.rounded() ? 0 : 2)
        let precision = Swift.min(Swift.max(digits, 0), 12)
        if decimals != nil { return n.formatted(.number.precision(.fractionLength(precision))) + suffix }
        return n.formatted(.number.precision(.fractionLength(0...precision))) + suffix
    }
}

private extension JSONValue {
    var containsVariable: Bool {
        switch self {
        case .string(let s): return s.contains("$")
        case .object(let d): return d.values.contains { $0.containsVariable }
        case .array(let a): return a.contains { $0.containsVariable }
        default: return false
        }
    }
}
