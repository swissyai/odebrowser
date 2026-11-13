import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A site icon ready for a tab to wear: bytes the favicon store keeps and the
/// decoder reads at once, with the size of the image they hold. An icon file
/// holding several images, such as a `.ico`, keeps only its largest; one too
/// large for the store, or larger than a tab ever draws, is redrawn smaller
/// as a PNG.
struct BrowserSiteIconImage: Sendable {
    // MARK: - Static Variables

    /// The largest side a stored icon keeps, in pixels.
    static let maximumSide = 256
    /// What a stored icon may be, the cap the favicon store enforces.
    static let maximumByteCount = BrowserFaviconCapture.maximumByteCount
    /// How far from square an icon may be and still fill a tile.
    private static let squareTolerance = 0.8

    // MARK: - Variables

    let data: Data
    let width: Int
    let height: Int

    /// The image's shorter side, which says how sharp it stays on a tile.
    var side: Int { min(width, height) }

    var isSquare: Bool {
        Double(min(width, height)) / Double(max(width, height, 1)) >= Self.squareTolerance
    }

    /// Whether the icon is large and square enough that no other is needed.
    var isLarge: Bool {
        isSquare && side >= BrowserSiteIconCandidate.largeSide
    }

    // MARK: - Initializers

    /// The icon `data` holds, or nil when it holds no image ImageIO can draw.
    init?(raster data: Data) {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var largest = 0
        var largestSize = (width: 0, height: 0)
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            if width * height > largestSize.width * largestSize.height {
                largest = index
                largestSize = (width, height)
            }
        }
        guard largestSize.width > 0, largestSize.height > 0 else { return nil }
        let keepsBytes =
            largest == 0 && max(largestSize.width, largestSize.height) <= Self.maximumSide
            && data.count <= Self.maximumByteCount
        if keepsBytes {
            // A first image that cannot be drawn makes bytes the decoder
            // would fail on too.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 16,
            ]
            guard CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else { return nil }
            self.data = data
            width = largestSize.width
            height = largestSize.height
            return
        }
        // A busy image can encode past the store's cap at the largest side;
        // half that side still covers every tile.
        for side in [Self.maximumSide, Self.maximumSide / 2] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, largest, options as CFDictionary),
                let png = Self.png(image)
            else { return nil }
            guard png.count <= Self.maximumByteCount else { continue }
            self.data = png
            width = image.width
            height = image.height
            return
        }
        return nil
    }

    // MARK: - Actions - Encoding

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
