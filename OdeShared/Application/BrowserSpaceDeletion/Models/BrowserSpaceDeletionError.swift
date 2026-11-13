import Foundation

enum BrowserSpaceDeletionError: LocalizedError, Equatable {
    case missingSpace
    case alreadyDeleting
    /// An engine could not erase everything it keeps for the Space's profile.
    case dataNotErased

    var errorDescription: String? {
        switch self {
        case .missingSpace:
            "That Space no longer exists."
        case .alreadyDeleting:
            "Ode is already deleting that Space."
        case .dataNotErased:
            "Ode couldn’t finish removing this Space’s browser data. Try again."
        }
    }
}
