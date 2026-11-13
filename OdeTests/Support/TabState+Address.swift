import Foundation

@testable import Ode

extension TabState {
    /// The tab's address, or nil when it holds none that parses.
    var address: URL? {
        url.flatMap(URL.init(string:))
    }
}
