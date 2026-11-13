import SwiftUI

/// How a status reads at a glance: settled, needing the person, or in
/// trouble. A status that is none of these has no tone and stays in its
/// view's quiet style. Objects that report a status carry its tone, so views
/// draw the same status in the same colour everywhere.
struct OdeStatusTone: Hashable, Sendable {
    // MARK: - Static Variables

    static let success = OdeStatusTone(name: "success", color: OdeColor.success)
    static let warning = OdeStatusTone(name: "warning", color: OdeColor.warning)
    static let danger = OdeStatusTone(name: "danger", color: OdeColor.danger)

    // MARK: - Variables

    let name: String
    /// The colour the status's words, glyph or badge draw in.
    let color: Color

    // MARK: - Initializers

    private init(name: String, color: Color) {
        self.name = name
        self.color = color
    }

    // MARK: - Actions - Identity

    static func == (lhs: OdeStatusTone, rhs: OdeStatusTone) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
