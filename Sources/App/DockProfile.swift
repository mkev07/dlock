import Foundation

struct DLockProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var displayID: String
    var orientation: DockOrientation
    var autohide: Bool

    init(id: UUID = UUID(), name: String, displayID: String, orientation: DockOrientation = .bottom, autohide: Bool = false) {
        self.id = id
        self.name = name
        self.displayID = displayID
        self.orientation = orientation
        self.autohide = autohide
    }

    static func == (lhs: DLockProfile, rhs: DLockProfile) -> Bool {
        lhs.id == rhs.id
    }
}
