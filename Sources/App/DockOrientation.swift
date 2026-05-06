import Foundation

enum DockOrientation: String, Codable, CaseIterable {
    case bottom = "bottom"
    case left = "left"
    case right = "right"

    var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .left:   return "Left"
        case .right:  return "Right"
        }
    }

    var symbolName: String {
        switch self {
        case .bottom: return "arrow.down.to.line"
        case .left:   return "arrow.left.to.line"
        case .right:  return "arrow.right.to.line"
        }
    }
}
