import Foundation

/// A queryless request to open fresh input in the receiving scene. This route
/// never carries browsing context or text across the widget/app boundary.
struct BrowserCommandLink: Equatable, Sendable {
    // MARK: - Static Variables

    static let newQuery = BrowserCommandLink()

    // MARK: - Variables

    var url: URL {
        guard let url = URL(string: "ode://command/new") else {
            preconditionFailure("The fixed Command Bar route always forms a URL.")
        }
        return url
    }

    // MARK: - Initializers

    private init() {}

    init?(url: URL) {
        // Accept one spelling only, including no empty query or fragment,
        // encoded path aliases, credentials, port, or additional path.
        guard url.absoluteString == Self.newQuery.url.absoluteString else { return nil }
        self = .newQuery
    }
}
