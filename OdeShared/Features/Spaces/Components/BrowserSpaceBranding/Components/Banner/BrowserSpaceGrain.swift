import CoreGraphics
import SwiftUI

/// A fine grain over a Space's ground: one tile of seeded noise, made once
/// and repeated across the surface, laid over the ground in soft light so it
/// keeps the ground's color and only roughens it. It draws nothing per
/// frame, so the ground slides between Spaces as smoothly without it.
struct BrowserSpaceGrain: View {
    // MARK: - Static Variables

    /// The tile's side in pixels, drawn at two pixels a point.
    nonisolated static let tileSide = 128
    /// How strongly the grain shows in each appearance; a dark ground needs
    /// more to show the same grain.
    nonisolated static let lightOpacity = 0.18
    nonisolated static let darkOpacity = 0.26

    @MainActor private static let tile = makeTile()

    // MARK: - Variables

    let colorScheme: ColorScheme

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.softLight)
                .opacity(colorScheme == .dark ? Self.darkOpacity : Self.lightOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions - Drawing

    /// The grain's tile: gray noise, the same every launch.
    nonisolated static func makeTile(side: Int = tileSide, seed: UInt64 = 0xC2E5_7A11) -> CGImage? {
        var generator = BrowserSpaceTextureGenerator(seed: seed)
        let pixels = (0..<(side * side)).map { _ in UInt8((generator.nextUnit() * 255).rounded()) }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
