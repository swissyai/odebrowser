import Foundation

enum BrowserContentBlockingError: LocalizedError {
    case compilationFailed
    case ruleListUnavailable

    var errorDescription: String? {
        switch self {
        case .compilationFailed:
            "Ode couldn’t compile its native content-blocking rules."
        case .ruleListUnavailable:
            "Ode’s native content-blocking rules are unavailable."
        }
    }
}
