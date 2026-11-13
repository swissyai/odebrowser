import SwiftUI

/// Ode's mark, drawn from ``OdeMarkGeometry``.
///
/// `.fitted` fills the frame with the O and its flap, for headers beside the
/// name and for favicons; `.onCanvas` places the mark where the app icon
/// does, at 600 of 1024 points, for a mark on its own tile. At 32 points and
/// below the fold gives way to a straight coral corner. At every size the
/// flap casts a soft curl shadow on the blue, its blur scaled with the mark
/// and kept to a floor so a 16-point mark still shows its corner lifting;
/// the small mark's falls along its straight corner.
struct OdeMark: View, @MainActor Animatable {
    // MARK: - Types

    enum Style: Sendable {
        /// The blue O and the coral flap, lighter blue in dark.
        case color
        /// One tone, the current foreground, with the flap at half strength.
        case mono
    }

    enum Placement: Sendable {
        case fitted
        case onCanvas
    }

    enum Finish: Sendable {
        /// Flat fills only, as the app icon draws the mark.
        case flat
        /// A soft shadow on the blue under the fold, as if the flap had just
        /// lifted: the mark as the app shows it.
        case curlShadow
    }

    // MARK: - Variables

    var style: Style = .color
    var placement: Placement = .fitted
    var finish: Finish = .curlShadow
    /// How far the flap is lifted, from 0 at rest to 1, for the one moment
    /// it settles; see ``OdeMarkDip``.
    var lift: CGFloat = 0

    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let (transform, scale) = canvasTransform(in: size)
            // Drawn from the simple outlines, the O and its counter as one
            // even-odd path: the paths the shapes' subtraction makes have over a
            // thousand segments, which Canvas rasterizes unevenly at large sizes.
            let shape = { (path: CGPath) in Path(path).applying(transform) }
            let flapMotion = OdeMarkGeometry.flapLift(lift)
            let moved = { (path: CGPath) in Path(path).applying(flapMotion.concatenating(transform)) }
            let isSmall = side <= OdeMarkGeometry.smallSide
            let corner = isSmall ? OdeMarkGeometry.smallCorner : OdeMarkGeometry.beyondFold
            let counter = shape(OdeMarkGeometry.counter)
            var ring = shape(OdeMarkGeometry.outer)
            ring.addPath(counter)
            let lifted = moved(corner)
            var flap = moved(OdeMarkGeometry.flapCorner)
            flap.addPath(moved(OdeMarkGeometry.counter))
            let evenOdd = FillStyle(eoFill: true)
            let ringShading: GraphicsContext.Shading
            let flapShading: GraphicsContext.Shading
            switch style {
            case .color:
                ringShading = .color(OdeMarkPalette.ring(in: colorScheme))
                flapShading = .color(OdeMarkPalette.flap)
            case .mono:
                ringShading = .style(.foreground)
                flapShading = .style(.foreground.opacity(0.5))
            }
            let drawsShadow = style == .color && finish == .curlShadow

            // The blue runs on under the flap and the coral is laid over it,
            // so the fold has one edge and no seam. One tone draws its flap at
            // half strength, so there the blue is cut away beneath it.
            if style == .mono {
                context.drawLayer { layer in
                    layer.fill(ring, with: ringShading, style: evenOdd)
                    layer.blendMode = .destinationOut
                    layer.fill(shape(corner), with: .color(.black))
                }
            } else {
                context.fill(ring, with: ringShading, style: evenOdd)
            }
            if drawsShadow {
                // The curl's shadow lands only on the blue, cast by the flap
                // the mark shows: the folded one, or the small straight corner.
                context.drawLayer { shadow in
                    shadow.clip(to: ring, style: evenOdd)
                    shadow.addFilter(.blur(radius: OdeMarkGeometry.curlShadowBlur(scale: scale, lift: lift)))
                    let fall = flapMotion.concatenating(OdeMarkGeometry.curlShadowOffset(lift, scale: scale))
                    let caster = isSmall ? OdeMarkGeometry.smallFlap : OdeMarkGeometry.flap
                    shadow.fill(
                        Path(caster).applying(fall.concatenating(transform)),
                        with: .color(OdeMarkPalette.curlShadow), style: evenOdd)
                }
            }
            context.drawLayer { layer in
                layer.clip(to: lifted)
                layer.fill(flap, with: flapShading, style: evenOdd)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    /// The transform from the canvas into `size`, and its scale.
    private func canvasTransform(in size: CGSize) -> (CGAffineTransform, CGFloat) {
        switch placement {
        case .onCanvas:
            let side = min(size.width, size.height)
            let scale = side / OdeMarkGeometry.canvas
            let transform = CGAffineTransform(
                translationX: (size.width - side) / 2, y: (size.height - side) / 2
            )
            .scaledBy(x: scale, y: scale)
            return (transform, scale)
        case .fitted:
            let bounds = OdeMarkGeometry.bounds
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let transform = CGAffineTransform(
                translationX: (size.width - bounds.width * scale) / 2,
                y: (size.height - bounds.height * scale) / 2
            )
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
            return (transform, scale)
        }
    }
}

/// The mark's one moment: where it first shows large in a session, its flap
/// starts lifted and settles back, its curl shadow easing with it. Reduce
/// Motion, Low Power Mode and an inactive window skip it, and it plays once.
@MainActor
final class OdeMarkDip {
    static let session = OdeMarkDip()

    private var hasPlayed = false

    /// Whether the moment plays now; once it has, it never plays again.
    func claim(
        reduceMotion: Bool, isActive: Bool,
        lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) -> Bool {
        guard !hasPlayed, !reduceMotion, !lowPower, isActive else { return false }
        hasPlayed = true
        return true
    }
}

/// The mark's colors, shared with the icon's layers.
enum OdeMarkPalette {
    static let ringLight = Color(red: 48 / 255, green: 80 / 255, blue: 240 / 255)
    static let ringDark = Color(red: 110 / 255, green: 139 / 255, blue: 255 / 255)
    static let flap = Color(red: 240 / 255, green: 122 / 255, blue: 112 / 255)
    /// The curl shadow: deep blue at 55%, as in the drawing.
    static let curlShadow = Color(red: 10 / 255, green: 26 / 255, blue: 107 / 255).opacity(0.55)

    static func ring(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? ringDark : ringLight
    }
}

#if DEBUG
    #Preview("Mark") {
        HStack(spacing: 24) {
            OdeMark(finish: .curlShadow).frame(width: 96, height: 96)
            OdeMark().frame(width: 96, height: 96)
            OdeMark().frame(width: 32, height: 32)
            OdeMark(style: .mono).frame(width: 32, height: 32)
            OdeMark().frame(width: 16, height: 16)
        }
        .padding()
    }
#endif
