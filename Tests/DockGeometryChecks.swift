import AppKit

/// Offline regression checks; no input injection or Dock setting changes.
@main struct DockGeometryChecks {
    static func main() {
        let display = CGRect(x: 2056, y: -210, width: 1920, height: 1080)
        let cases: [(String, CGPoint, CGSize, DockOrientation)] = [
            ("visible bottom", CGPoint(x: 2130, y: 820), CGSize(width: 1772, height: 50), .bottom),
            ("hidden bottom", CGPoint(x: 2130, y: 870), CGSize(width: 1772, height: 50), .bottom),
            ("visible left", CGPoint(x: 2056, y: 0), CGSize(width: 50, height: 600), .left),
            ("hidden left", CGPoint(x: 2006, y: 0), CGSize(width: 50, height: 600), .left),
            ("visible right", CGPoint(x: 3926, y: 0), CGSize(width: 50, height: 600), .right),
            ("hidden right", CGPoint(x: 3976, y: 0), CGSize(width: 50, height: 600), .right)
        ]
        var failures = 0
        for (name, position, size, orientation) in cases {
            let point = DockGuardian.screenProbePoint(position: position, size: size, orientation: orientation)
            if display.contains(point) { print("PASS: \(name)") }
            else { print("FAIL: \(name): \(point)"); failures += 1 }
        }
        // A display below the target contains the hidden Dock's old center.
        let below = CGRect(x: 2056, y: 870, width: 1920, height: 1080)
        let anchor = DockGuardian.screenProbePoint(position: CGPoint(x: 2130, y: 870),
            size: CGSize(width: 1772, height: 50), orientation: .bottom)
        if !below.contains(anchor) { print("PASS: stacked neighbour cannot steal hidden Dock detection") }
        else { print("FAIL: stacked neighbour selected"); failures += 1 }
        let builtin = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let exposed = DockController.placementPoint(in: builtin, orientation: .right, displays: [builtin, display])
        if exposed == CGPoint(x: 2055, y: 1099.5) { print("PASS: shared right seam avoided") }
        else { print("FAIL: shared right seam"); failures += 1 }
        let blocking = CGRect(x: 2056, y: 0, width: 1920, height: 1329)
        if DockController.placementPoint(in: builtin, orientation: .right, displays: [builtin, blocking]) == nil {
            print("PASS: fully covered edge rejected")
        } else { print("FAIL: covered edge accepted"); failures += 1 }
        exit(failures == 0 ? 0 : 1)
    }
}
