import Foundation
import CoreGraphics

@main
struct DisplayLayoutChecks {
    static func main() {
        let upper = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let lower = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let side = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        check(DockLayoutGeometry.placementPoint(in: upper, orientation: .bottom, displays: [upper, side]) != nil,
              "side-by-side screens need no rearrangement")
        check(DockLayoutGeometry.placementPoint(in: upper, orientation: .bottom, displays: [upper, lower]) == nil,
              "aligned stacked screens block the upper bottom edge")
        guard let suggestion = DockLayoutGeometry.bottomEdgeSuggestion(for: upper, displays: [upper, lower]) else {
            fatalError("Missing stacked-display suggestion")
        }
        check(DockLayoutGeometry.placementPoint(in: suggestion.frame, orientation: .bottom, displays: [suggestion.frame, lower]) != nil,
              "suggested offset exposes an edge using the same placement geometry")
        check(suggestion.frame.minY == upper.minY && suggestion.frame.height == upper.height,
              "suggestion preserves vertical position and screen size")
        let offset = upper.offsetBy(dx: -100, dy: 0)
        check(DockLayoutGeometry.bottomEdgeSuggestion(for: offset, displays: [offset, lower]) == nil,
              "already offset stacked layouts are left alone")
        let wider = CGRect(x: -200, y: 0, width: 1840, height: 900)
        check(DockLayoutGeometry.bottomEdgeSuggestion(for: wider, displays: [wider, lower]) == nil,
              "a wider upper display already has an exposed bottom edge")
        let leftNeighbour = upper.offsetBy(dx: -1440, dy: 0)
        let rightSuggestion = DockLayoutGeometry.bottomEdgeSuggestion(for: upper, displays: [upper, lower, leftNeighbour])
        check(rightSuggestion?.direction == "right", "suggestion avoids overlapping the left neighbour")
        check(DockLayoutGeometry.bottomEdgeSuggestion(for: upper, displays: [upper, lower, leftNeighbour, side]) == nil,
              "no unsafe offset is suggested when both directions overlap other screens")
        let lowerLeft = CGRect(x: 0, y: 900, width: 720, height: 900)
        let lowerRight = CGRect(x: 720, y: 900, width: 720, height: 900)
        check(DockLayoutGeometry.placementPoint(in: upper, orientation: .bottom, displays: [upper, lowerLeft, lowerRight]) == nil,
              "multiple lower displays can cover the entire edge together")
        check(DockLayoutGeometry.bottomEdgeSuggestion(for: upper, displays: [upper, lowerLeft, lowerRight]) != nil,
              "union of lower displays receives a valid offset suggestion")
        let appKitUpper = CGRect(x: -1440, y: 900, width: 1440, height: 900)
        let appKitLower = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let converted = [appKitUpper, appKitLower].map(DockLayoutGeometry.quartzFrame(fromAppKit:))
        check(DockLayoutGeometry.placementPoint(in: converted[0], orientation: .bottom, displays: converted) == nil,
              "AppKit coordinate conversion preserves stacked layouts with negative coordinates")
        check(DockLayoutGeometry.placementPoint(in: .zero, orientation: .bottom, displays: [.zero]) == nil,
              "empty display bounds are rejected")
    }

    static func check(_ result: Bool, _ message: String) {
        guard result else { fatalError(message) }
        print("PASS: \(message)")
    }
}
