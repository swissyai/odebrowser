import Foundation

struct BrowserFaviconColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    var iconAccent: BrowserTabIconAccent {
        BrowserTabIconAccent(red: red, green: green, blue: blue)
    }

    /// The color's OKLab coordinate, where the palette averages.
    var perceptualComponents: SIMD3<Double> {
        OKLCHColor.lab(linear: SIMD3(OKLCHColor.decode(red), OKLCHColor.decode(green), OKLCHColor.decode(blue)))
    }

    /// The color an OKLab coordinate names, each channel clamped to sRGB
    /// rather than gamut-mapped as the Space roles are.
    init(perceptualComponents value: SIMD3<Double>) {
        let linear = OKLCHColor.linear(lab: value)
        self.init(
            red: OKLCHColor.encode(linear.x), green: OKLCHColor.encode(linear.y), blue: OKLCHColor.encode(linear.z))
    }
}
