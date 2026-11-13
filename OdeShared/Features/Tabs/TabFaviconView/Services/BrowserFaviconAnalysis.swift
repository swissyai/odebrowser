import CoreGraphics
import Foundation

/// A decoded site icon with what is known about how it reads.
struct BrowserFaviconDecodedImage: Sendable {
    let image: CGImage
    let analysis: BrowserFaviconAnalysis
}

/// An icon's tone, and for a monochrome mark its inverted copy, made once
/// per decoded image so drawing it only picks between the two.
struct BrowserFaviconAnalysis: Sendable {
    // MARK: - Static Variables

    /// The side of the small copy the tone is measured on.
    static let sampleSide = 32
    /// Pixels fainter than this are left out of the tone.
    static let minimumAlpha = 0.05

    // MARK: - Variables

    let tone: BrowserFaviconTone?
    let invertedImage: CGImage?

    // MARK: - Initializers

    init(tone: BrowserFaviconTone?, invertedImage: CGImage?) {
        self.tone = tone
        self.invertedImage = invertedImage
    }

    init(image: CGImage) {
        let tone = Self.tone(of: image)
        self.init(tone: tone, invertedImage: tone?.isMonochrome == true ? Self.inverted(image) : nil)
    }

    // MARK: - Actions - Measuring

    static func tone(of image: CGImage) -> BrowserFaviconTone? {
        guard let pixels = rgba(of: image, width: sampleSide, height: sampleSide) else { return nil }
        var bands = Array(repeating: 0.0, count: BrowserFaviconTone.bandCount)
        var chromas: [(chroma: Double, weight: Double)] = []
        chromas.reserveCapacity(sampleSide * sampleSide)
        var totalWeight = 0.0
        var chromaSum = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= minimumAlpha else { continue }
            let color = OKLCHColor(
                srgbRed: min(1, Double(pixels[offset]) / 255 / alpha),
                green: min(1, Double(pixels[offset + 1]) / 255 / alpha),
                blue: min(1, Double(pixels[offset + 2]) / 255 / alpha))
            bands[BrowserFaviconTone.band(forLightness: color.lightness)] += alpha
            chromas.append((color.chroma, alpha))
            chromaSum += color.chroma * alpha
            totalWeight += alpha
        }
        guard totalWeight > 0 else {
            return BrowserFaviconTone(lightnessBands: bands, meanChroma: 0, peakChroma: 0)
        }
        chromas.sort { $0.chroma < $1.chroma }
        var accumulated = 0.0
        var peak = chromas.last?.chroma ?? 0
        for entry in chromas {
            accumulated += entry.weight
            if accumulated >= totalWeight * 0.9 {
                peak = entry.chroma
                break
            }
        }
        return BrowserFaviconTone(
            lightnessBands: bands.map { $0 / totalWeight }, meanChroma: chromaSum / totalWeight, peakChroma: peak)
    }

    /// `image` with each pixel's color inverted and its opacity kept.
    static func inverted(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
            var pixels = rgba(of: image, width: width, height: height)
        else { return nil }
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[offset + 3]
            guard alpha > 0 else { continue }
            // Premultiplied: the inverse of color c under alpha a is a - c.
            for channel in 0..<3 { pixels[offset + channel] = alpha &- min(alpha, pixels[offset + channel]) }
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }

    private static func rgba(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
