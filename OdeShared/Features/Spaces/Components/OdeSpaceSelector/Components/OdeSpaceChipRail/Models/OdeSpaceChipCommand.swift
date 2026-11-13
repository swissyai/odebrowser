import SwiftUI

/// One context-menu command on a Space chip.
struct OdeSpaceChipCommand: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void

    static func remove(_ perform: @escaping () -> Void) -> Self {
        OdeSpaceChipCommand(
            id: "remove",
            title: "Remove Space",
            systemImage: "trash",
            isDestructive: true,
            perform: perform
        )
    }
}
