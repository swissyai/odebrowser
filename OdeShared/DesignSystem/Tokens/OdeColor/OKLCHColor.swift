import Foundation
import SwiftUI
import Synchronization

/// A color in OKLCH: perceived lightness from 0 for black to 1 for white,
/// chroma from 0 for gray, and hue in degrees. Equal steps of lightness look
/// equally far apart at every hue, so a role drawn at one lightness keeps its
/// contrast whatever a Space's hue (Björn Ottosson's OKLab, in polar form).
struct OKLCHColor: Equatable, Sendable {
    // MARK: - Static Variables

    private static let maximumChromaCacheCapacity = 65_536
    private static let maximumChromaCache = Mutex<[GamutKey: Double]>([:])

    // MARK: - Types

    private struct GamutKey: Hashable {
        let lightness: Double
        let hue: Double
    }

    // MARK: - Variables

    var lightness: Double
    var chroma: Double
    var hue: Double

    // MARK: - Initializers

    init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = max(0, chroma)
        self.hue = Self.normalizedHue(hue)
    }

    /// The color an encoded sRGB value shows, each component from 0 to 1.
    init(srgbRed red: Double, green: Double, blue: Double) {
        self.init(lab: Self.lab(linear: SIMD3(Self.decode(red), Self.decode(green), Self.decode(blue))))
    }

    /// The color an OKLab coordinate names: lightness, then the green–red
    /// and blue–yellow axes.
    init(lab: SIMD3<Double>) {
        let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        let hue = chroma < 1e-9 ? 0 : atan2(lab.z, lab.y) * 180 / .pi
        self.init(lightness: lab.x, chroma: chroma, hue: hue)
    }

    // MARK: - Variables - Conversions

    /// The color's OKLab coordinate, where mixing is linear.
    var lab: SIMD3<Double> {
        let radians = hue * .pi / 180
        return SIMD3(lightness, chroma * cos(radians), chroma * sin(radians))
    }

    /// Linear-light sRGB components, outside 0...1 when the color is out of
    /// the sRGB gamut.
    var linearSRGB: SIMD3<Double> {
        Self.linear(lab: lab)
    }

    var isInSRGBGamut: Bool {
        let value = linearSRGB
        let tolerance = 1e-7
        return value.min() >= -tolerance && value.max() <= 1 + tolerance
    }

    /// This color with its chroma reduced, at the same lightness and hue,
    /// until sRGB can show it: CSS Color 4's gamut mapping intent, which
    /// keeps the hue a plain clip would shift.
    var mappedToSRGB: OKLCHColor {
        guard lightness > 0, lightness < 1 else {
            return OKLCHColor(lightness: min(max(lightness, 0), 1), chroma: 0, hue: hue)
        }
        let limit = Self.maximumChroma(lightness: lightness, hue: hue)
        return OKLCHColor(lightness: lightness, chroma: min(chroma, limit), hue: hue)
    }

    /// Encoded sRGB components from 0 to 1, after gamut mapping.
    var srgbComponents: SIMD3<Double> {
        let linear = mappedToSRGB.linearSRGB
        return SIMD3(Self.encode(linear.x), Self.encode(linear.y), Self.encode(linear.z))
    }

    var color: Color {
        let components = srgbComponents
        return Color(.sRGB, red: components.x, green: components.y, blue: components.z, opacity: 1)
    }

    var brandColor: BrandColor {
        let components = srgbComponents
        return BrandColor(red: components.x, green: components.y, blue: components.z)
    }

    /// The color as `#RRGGBB`, after gamut mapping.
    var hexString: String {
        let components = srgbComponents
        return "#"
            + [components.x, components.y, components.z]
            .map { String(format: "%02X", Int(($0 * 255).rounded())) }
            .joined()
    }

    /// WCAG relative luminance of the gamut-mapped color.
    var relativeLuminance: Double {
        Self.luminance(srgb: srgbComponents)
    }

    // MARK: - Actions - Contrast

    /// The WCAG 2 contrast ratio between two colors, from 1 to 21.
    static func contrast(_ first: OKLCHColor, _ second: OKLCHColor) -> Double {
        contrast(luminance: first.relativeLuminance, second.relativeLuminance)
    }

    /// The WCAG 2 contrast ratio between two encoded sRGB colors, such as a
    /// translucent color already composited over its ground.
    static func contrast(srgb first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        contrast(luminance: luminance(srgb: first), luminance(srgb: second))
    }

    /// The WCAG 2 contrast ratio between two relative luminances, from 1 to
    /// 21: every contrast floor Ode checks is measured with this.
    static func contrast(luminance first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// WCAG relative luminance of an encoded sRGB color.
    static func luminance(srgb components: SIMD3<Double>) -> Double {
        luminance(linear: SIMD3(decode(components.x), decode(components.y), decode(components.z)))
    }

    /// WCAG relative luminance of linear-light sRGB components.
    static func luminance(linear components: SIMD3<Double>) -> Double {
        0.2126 * components.x + 0.7152 * components.y + 0.0722 * components.z
    }

    /// APCA lightness contrast (APCA-W3 0.0.98G) of `text` over
    /// `background`, both encoded sRGB, as an absolute Lc from 0 to about
    /// 106: the second check beside WCAG 2.
    static func apcaContrast(text: SIMD3<Double>, background: SIMD3<Double>) -> Double {
        func screenLuminance(_ rgb: SIMD3<Double>) -> Double {
            let y = 0.2126729 * pow(rgb.x, 2.4) + 0.7151522 * pow(rgb.y, 2.4) + 0.0721750 * pow(rgb.z, 2.4)
            return y < 0.022 ? y + pow(0.022 - y, 1.414) : y
        }
        let (textY, backgroundY) = (screenLuminance(text), screenLuminance(background))
        guard abs(backgroundY - textY) >= 0.0005 else { return 0 }
        if backgroundY > textY {
            let contrast = (pow(backgroundY, 0.56) - pow(textY, 0.57)) * 1.14
            return contrast < 0.1 ? 0 : (contrast - 0.027) * 100
        }
        let contrast = (pow(backgroundY, 0.65) - pow(textY, 0.62)) * 1.14
        return contrast > -0.1 ? 0 : -(contrast + 0.027) * 100
    }

    // MARK: - Actions - Gamut

    /// The largest chroma sRGB shows at this lightness and hue, found by
    /// bisection and kept, since roles ask for the same few lightnesses
    /// again and again.
    static func maximumChroma(lightness: Double, hue: Double) -> Double {
        guard lightness > 0, lightness < 1 else { return 0 }
        // Nearby inputs can straddle a gamut or contrast floor. Reusing a
        // rounded key made the answer depend on which caller warmed it first.
        let key = GamutKey(lightness: lightness, hue: normalizedHue(hue))
        if let known = maximumChromaCache.withLock({ $0[key] }) { return known }
        var low = 0.0
        var high = 0.5
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if OKLCHColor(lightness: lightness, chroma: middle, hue: hue).isInSRGBGamut {
                low = middle
            } else {
                high = middle
            }
        }
        maximumChromaCache.withLock { cache in
            // Continuous color edits produce distinct exact keys. Keep that
            // precision without retaining every color the picker ever crossed.
            if cache.count >= maximumChromaCacheCapacity { cache.removeAll(keepingCapacity: true) }
            cache[key] = low
        }
        return low
    }

    // MARK: - Actions - Transfer

    /// The sRGB transfer function, from linear light to an encoded value.
    static func encode(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped > 0.0031308 ? 1.055 * pow(clamped, 1 / 2.4) - 0.055 : 12.92 * clamped
    }

    /// The inverse transfer function, from an encoded value to linear light.
    static func decode(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    // MARK: - Actions - OKLab

    /// The OKLab coordinate of linear-light sRGB components.
    static func lab(linear rgb: SIMD3<Double>) -> SIMD3<Double> {
        let l = cbrt(0.4122214708 * rgb.x + 0.5363325363 * rgb.y + 0.0514459929 * rgb.z)
        let m = cbrt(0.2119034982 * rgb.x + 0.6806995451 * rgb.y + 0.1073969566 * rgb.z)
        let s = cbrt(0.0883024619 * rgb.x + 0.2817188376 * rgb.y + 0.6299787005 * rgb.z)
        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// The linear-light sRGB components of an OKLab coordinate, outside
    /// 0...1 when it is out of the sRGB gamut.
    static func linear(lab: SIMD3<Double>) -> SIMD3<Double> {
        let l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let (l3, m3, s3) = (l * l * l, m * m * m, s * s * s)
        return SIMD3(
            4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        )
    }

    // MARK: - Actions - Hue

    private static func normalizedHue(_ hue: Double) -> Double {
        guard hue.isFinite else { return 0 }
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}

extension OKLCHColor {
    /// The color a stored brand color shows.
    init(_ color: BrandColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue)
    }
}
