import Foundation
import CoreGraphics

/// Uses the safe content viewport, never a device model or physical screen size.
struct DashboardLayout {
    static let padding: CGFloat = 20
    let width: CGFloat
    let division: CGRect?

    init(width: CGFloat, division: CGRect? = nil) {
        self.width = max(0, width - 2 * Self.padding)
        if let division, division.minX > Self.padding, division.maxX < width - Self.padding {
            self.division = division
        } else {
            self.division = nil
        }
    }

    var leadingWidth: CGFloat { max(0, (division?.minX ?? 0) - Self.padding) }
    var trailingWidth: CGFloat { max(0, width + Self.padding - (division?.maxX ?? 0)) }

    func capacity(compact: Bool, gauge: Bool, wide: Bool, accessible: Bool) -> Int {
        let available = division == nil ? width : min(leadingWidth, trailingWidth)
        if accessible || (!compact && wide) { return 1 }
        let minimum: CGFloat = compact ? 140 : gauge ? 220 : 320
        let spacing: CGFloat = compact ? 12 : 16
        let limit = compact ? 4 : gauge ? 3 : 2
        let count = max(1, min(limit, Int((available + spacing) / (minimum + spacing))))
        // A partially folded display always leaves a gap between its two regions.
        return division == nil ? count : min(compact ? 4 : 2, count * 2)
    }

    func panelWidth(at index: Int, capacity: Int, spacing: CGFloat) -> CGFloat {
        guard division != nil else {
            return max(0, (width - CGFloat(capacity - 1) * spacing) / CGFloat(capacity))
        }
        if capacity == 1 { return trailingWidth }
        let perSide = capacity / 2
        let regionWidth = index < perSide ? leadingWidth : trailingWidth
        return max(0, (regionWidth - CGFloat(perSide - 1) * spacing) / CGFloat(perSide))
    }

    func gap(after index: Int, capacity: Int, spacing: CGFloat) -> CGFloat {
        if let division, capacity > 1, index == capacity / 2 - 1 {
            return division.width
        }
        return spacing
    }
}
