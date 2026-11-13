import SwiftUI

/// The solid color a site's pill takes in the Command Bar once Tab enters
/// it: the site's brand color under white text, or under near-black text for
/// a brand too light for white. White wins when the brand reads under it, or
/// does after a small darkening; otherwise the text turns dark, and a brand
/// too dark even for that is lightened until it reads. Text always reaches
/// ``minimumContrast`` against the fill.
struct BrowserSearchProviderFill: Equatable, Sendable {
    // MARK: - Static Variables

    static let minimumContrast = 4.5
    /// How far the brand may darken, in OKLCH lightness, to keep white text.
    static let maximumDarkening = 0.10

    private static let white = OKLCHColor(lightness: 1, chroma: 0, hue: 0)
    private static let ink = OKLCHColor(srgbRed: 0.08, green: 0.08, blue: 0.09)

    // MARK: - Variables

    let fill: OKLCHColor
    let usesLightText: Bool

    var fillColor: Color { fill.color }
    var textColor: Color { usesLightText ? .white : Self.ink.color }

    /// The pill's text against its fill, as WCAG measures it.
    var contrast: Double {
        OKLCHColor.contrast(fill, usesLightText ? Self.white : Self.ink)
    }

    // MARK: - Initializers

    init(brand: BrandColor) {
        let base = OKLCHColor(brand)
        if OKLCHColor.contrast(base, Self.white) >= Self.minimumContrast {
            self.init(fill: base, usesLightText: true)
        } else if let darker = Self.lightness(
            from: base, toward: max(0, base.lightness - Self.maximumDarkening), against: Self.white)
        {
            self.init(fill: darker, usesLightText: true)
        } else if OKLCHColor.contrast(base, Self.ink) >= Self.minimumContrast {
            self.init(fill: base, usesLightText: false)
        } else {
            let lighter = Self.lightness(from: base, toward: 1, against: Self.ink) ?? Self.white
            self.init(fill: lighter, usesLightText: false)
        }
    }

    private init(fill: OKLCHColor, usesLightText: Bool) {
        self.fill = fill
        self.usesLightText = usesLightText
    }

    // MARK: - Actions

    /// The color nearest `base` in lightness, between it and `limit`, whose
    /// contrast with `text` reaches the minimum; nil if none on the way does.
    private static func lightness(from base: OKLCHColor, toward limit: Double, against text: OKLCHColor)
        -> OKLCHColor?
    {
        let at = { (lightness: Double) in OKLCHColor(lightness: lightness, chroma: base.chroma, hue: base.hue) }
        guard OKLCHColor.contrast(at(limit), text) >= minimumContrast else { return nil }
        var near = base.lightness
        var far = limit
        for _ in 0..<24 {
            let middle = (near + far) / 2
            if OKLCHColor.contrast(at(middle), text) >= minimumContrast {
                far = middle
            } else {
                near = middle
            }
        }
        return at(far)
    }
}
