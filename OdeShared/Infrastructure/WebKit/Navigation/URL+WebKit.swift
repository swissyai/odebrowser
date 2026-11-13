import Foundation

extension URL {
    /// WebKit's document keeps an `about:blank` fragment, but its NSURL
    /// getters escape the separator as part of the opaque path. Restore only
    /// that separator at the native boundary, without decoding the fragment.
    var webKitPageURL: URL {
        let prefix = "about:blank%23"
        guard absoluteString.hasPrefix(prefix) else { return self }
        return URL(string: "about:blank#" + absoluteString.dropFirst(prefix.count)) ?? self
    }
}
