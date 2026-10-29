import Foundation
import CoreGraphics

enum DockLayoutGeometry {
    struct Suggestion: Equatable {
        let frame: CGRect
        let direction: String
    }

    static func placementPoint(in bounds: CGRect, orientation: DockOrientation,
                               displays: [CGRect]) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0, !bounds.isInfinite else { return nil }
        let vertical = orientation != .bottom
        var segments = [(vertical ? bounds.minY : bounds.minX,
                         vertical ? bounds.maxY : bounds.maxX)]
        for other in displays where other != bounds {
            let adjacent: Bool
            switch orientation {
            case .left: adjacent = abs(other.maxX - bounds.minX) <= 2
            case .right: adjacent = abs(other.minX - bounds.maxX) <= 2
            case .bottom: adjacent = abs(other.minY - bounds.maxY) <= 2
            }
            guard adjacent else { continue }
            let low = vertical ? other.minY : other.minX
            let high = vertical ? other.maxY : other.maxX
            segments = segments.flatMap { start, end -> [(CGFloat, CGFloat)] in
                guard low < end && high > start else { return [(start, end)] }
                var remaining: [(CGFloat, CGFloat)] = []
                if low > start { remaining.append((start, min(low, end))) }
                if high < end { remaining.append((max(high, start), end)) }
                return remaining
            }
        }
        guard let segment = segments.filter({ $0.1 - $0.0 > 2 })
            .max(by: { $0.1 - $0.0 < $1.1 - $1.0 }) else { return nil }
        let middle = (segment.0 + segment.1) / 2
        switch orientation {
        case .left: return CGPoint(x: bounds.minX, y: middle)
        case .right: return CGPoint(x: bounds.maxX - 1, y: middle)
        case .bottom: return CGPoint(x: middle, y: bounds.maxY - 1)
        }
    }

    static func bottomEdgeSuggestion(for bounds: CGRect, displays: [CGRect]) -> Suggestion? {
        guard placementPoint(in: bounds, orientation: .bottom, displays: displays) == nil,
              bounds.width > 48 else { return nil }
        let others = displays.filter { $0 != bounds }
        let adjacent = others.filter { abs($0.minY - bounds.maxY) <= 2 }
        guard let left = adjacent.map(\.minX).min(),
              let right = adjacent.map(\.maxX).max() else { return nil }
        let exposedWidth = min(240, max(48, bounds.width * 0.2))
        let offsets = [left - bounds.minX - exposedWidth, right - bounds.maxX + exposedWidth]
        for offset in offsets.sorted(by: { abs($0) < abs($1) }) {
            let proposed = bounds.offsetBy(dx: offset, dy: 0)
            let overlaps = others.contains {
                let intersection = proposed.intersection($0)
                return intersection.width > 2 && intersection.height > 2
            }
            let remainsAdjacent = adjacent.contains {
                min(proposed.maxX, $0.maxX) - max(proposed.minX, $0.minX) > 2
            }
            guard !overlaps, remainsAdjacent,
                  placementPoint(in: proposed, orientation: .bottom, displays: others + [proposed]) != nil else { continue }
            return Suggestion(frame: proposed, direction: offset < 0 ? "left" : "right")
        }
        return nil
    }

    static func quartzFrame(fromAppKit frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: -frame.maxY, width: frame.width, height: frame.height)
    }
}
