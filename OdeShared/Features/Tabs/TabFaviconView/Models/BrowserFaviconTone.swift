import Foundation

/// How a site icon reads against what it is drawn on: the share of its drawn
/// area at each perceptual lightness, and whether it carries color. Measured
/// once per decoded image from a small copy of it, off the main thread.
struct BrowserFaviconTone: Equatable, Sendable {
    // MARK: - Static Variables

    /// Lightness bands, by OKLab lightness, the drawn area is sorted into.
    static let bandCount = 16
    /// An icon whose mean and near-peak chroma stay under these is a
    /// monochrome mark, which may be inverted; an icon with color never is.
    static let monochromeMeanChroma = 0.04
    static let monochromePeakChroma = 0.09

    // MARK: - Variables

    /// The share of the drawn area, weighted by opacity, in each lightness
    /// band; the shares add up to one, or are all zero for an empty icon.
    let lightnessBands: [Double]
    let meanChroma: Double
    /// The chroma that nine tenths of the drawn area stays under.
    let peakChroma: Double

    var isMonochrome: Bool {
        meanChroma < Self.monochromeMeanChroma && peakChroma < Self.monochromePeakChroma
    }

    // MARK: - Actions - Contrast

    /// The share of the drawn area that stands at least `minimumContrast`
    /// off a ground of relative luminance `groundLuminance`.
    func readableShare(againstGroundLuminance groundLuminance: Double, minimumContrast: Double) -> Double {
        lightnessBands.enumerated().reduce(0) { total, band in
            let luminance = Self.luminance(ofBand: band.offset)
            let contrast = OKLCHColor.contrast(luminance: luminance, groundLuminance)
            return contrast >= minimumContrast ? total + band.element : total
        }
    }

    /// The tone the icon would have with its colors inverted, as a
    /// monochrome mark is drawn when it would vanish into its ground.
    var inverted: BrowserFaviconTone {
        var bands = Array(repeating: 0.0, count: Self.bandCount)
        for (index, share) in lightnessBands.enumerated() where share > 0 {
            let encoded = OKLCHColor.encode(Self.luminance(ofBand: index))
            let invertedLuminance = OKLCHColor.decode(1 - encoded)
            bands[Self.band(forLightness: cbrt(invertedLuminance))] += share
        }
        return BrowserFaviconTone(lightnessBands: bands, meanChroma: meanChroma, peakChroma: peakChroma)
    }

    // MARK: - Actions - Bands

    static func band(forLightness lightness: Double) -> Int {
        min(bandCount - 1, max(0, Int(lightness * Double(bandCount))))
    }

    /// The relative luminance at a band's middle, for a neutral color.
    static func luminance(ofBand band: Int) -> Double {
        let lightness = (Double(band) + 0.5) / Double(bandCount)
        return lightness * lightness * lightness
    }
}

/// How a site icon is drawn so it reads on its ground. A readable icon is
/// drawn as the site made it; a monochrome mark that vanishes is inverted,
/// so a black mark turns white on a dark ground; an icon with color that
/// vanishes keeps its colors and sits on a small plate of the opposite
/// lightness.
enum BrowserFaviconTreatment: Equatable, Sendable {
    case asIs
    case inverted
    case plated(lightPlate: Bool)

    /// A pixel reads when it stands this far off the ground (WCAG ratio).
    static let readableContrast = 2.0
    /// An icon reads when at least this share of its drawn area does. A
    /// tile icon whose glyph reads, such as a white tile with a black letter
    /// on a light ground, is left as the site made it.
    static let readableShare = 0.1
    /// Grounds darker than this get a light plate, lighter ones a dark one.
    static let darkGroundLuminance = 0.18

    static func choose(for tone: BrowserFaviconTone, groundLuminance: Double) -> Self {
        let share = tone.readableShare(againstGroundLuminance: groundLuminance, minimumContrast: readableContrast)
        guard share < readableShare, tone.lightnessBands.contains(where: { $0 > 0 }) else { return .asIs }
        if tone.isMonochrome,
            tone.inverted.readableShare(againstGroundLuminance: groundLuminance, minimumContrast: readableContrast)
                > share
        {
            return .inverted
        }
        return .plated(lightPlate: groundLuminance < darkGroundLuminance)
    }
}
