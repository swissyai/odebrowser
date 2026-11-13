import CoreGraphics
import Foundation
import ImageIO

/// Synthetic site icons for the tests of finding and importing them.
enum SiteIconFixture {
    /// A square PNG `side` pixels across in one color.
    static func png(side: Int, red: CGFloat = 0.9) -> Data {
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let image = { () -> CGImage? in
                context.setFillColor(red: red, green: 0.2, blue: 0.1, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                return context.makeImage()
            }()
        else { preconditionFailure("A fixture icon could not be drawn.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            preconditionFailure("A fixture icon could not be encoded.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            preconditionFailure("A fixture icon could not be encoded.")
        }
        return data as Data
    }
}
