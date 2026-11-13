import Observation
import SwiftUI

/// The pictures cards show, fetched with the card before it appears and
/// kept for the session by address, so a card draws its picture at once and
/// never fetches while it shows.
@MainActor
@Observable
final class BrowserCommandPaletteCardImages {
    // MARK: - Static Variables

    static let shared = BrowserCommandPaletteCardImages()

    /// The most pictures kept.
    private static let capacity = 32

    // MARK: - Variables

    private var images: [String: Image] = [:]
    @ObservationIgnored private var order: [String] = []

    // MARK: - Actions - Keeping

    /// The picture kept for `address`, or nil.
    func image(for address: String) -> Image? { images[address] }

    /// Keeps the picture `data` holds for `address`, answering whether it
    /// was one.
    @discardableResult
    func keep(_ data: Data, for address: String) -> Bool {
        #if os(macOS)
            guard let picture = NSImage(data: data) else { return false }
            let image = Image(nsImage: picture)
        #else
            guard let picture = UIImage(data: data) else { return false }
            let image = Image(uiImage: picture)
        #endif
        if images[address] == nil { order.append(address) }
        images[address] = image
        while order.count > Self.capacity { images[order.removeFirst()] = nil }
        return true
    }
}
