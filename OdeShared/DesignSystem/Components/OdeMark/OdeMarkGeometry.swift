import CoreGraphics

/// Ode's mark: an organic blue O whose top-right corner lifts along an
/// S-shaped fold to show a coral underside. Every drawing of the mark, in the
/// app and in its icon (`tools/dev/generate-mark.swift` compiles this file),
/// comes from these paths, so the fold is one curve everywhere.
///
/// The shapes are measured in the drawing's own 385-unit space, where each
/// quarter of the O is a superellipse of its own roundness, and placed on the
/// icon's 1024-point canvas with the O 600 points wide, y pointing down. The
/// paths are built once, on the main actor, where every drawing of the mark
/// reads them; `CGPath` is not `Sendable`.
enum OdeMarkGeometry {
    // MARK: - Static Variables

    static let canvas: CGFloat = 1024

    /// The drawing's scale on the canvas: the O's 322 units become 600 points.
    static let scale: CGFloat = 600 / 322

    /// Places the drawing's space on the canvas, the O's center at (512, 516).
    static let placement = CGAffineTransform(translationX: 512 - 191 * scale, y: 516 - 197.5 * scale)
        .scaledBy(x: scale, y: scale)

    /// The O: rounder toward the lower left, squarer under the flap.
    @MainActor static let outer = placed(
        quadrantShape(
            center: CGPoint(x: 191, y: 197), left: 161, right: 161, top: 147, bottom: 148,
            exponents: Exponents(topLeft: 2.05, topRight: 2.7, bottomRight: 2.35, bottomLeft: 2.0)))

    /// The O's counter, a soft rounded square a little taller than wide.
    @MainActor static let counter = placed(
        quadrantShape(
            center: CGPoint(x: 193, y: 204), left: 74, right: 74, top: 82, bottom: 82,
            exponents: Exponents(uniform: 2.45)))

    /// The lifted flap's outline: the O with a squarer top-right quarter, so
    /// the flap stands a little proud of the O's corner, as a peeled sticker does.
    @MainActor static let flapCorner = placed(
        quadrantShape(
            center: CGPoint(x: 191, y: 197), left: 161, right: 161, top: 147, bottom: 148,
            exponents: Exponents(topLeft: 2.05, topRight: 3.8, bottomRight: 2.35, bottomLeft: 2.0)))

    /// The fold: one broad S, leaving the O's top edge heading down and
    /// sweeping out past its right edge.
    @MainActor static let fold: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 196, y: 40))
        path.addCurve(to: CGPoint(x: 260, y: 126), control1: CGPoint(x: 228, y: 50), control2: CGPoint(x: 246, y: 92))
        path.addCurve(to: CGPoint(x: 362, y: 186), control1: CGPoint(x: 274, y: 160), control2: CGPoint(x: 298, y: 178))
        return placed(path)
    }()

    /// Everything beyond the fold, toward the top-right corner of the canvas.
    @MainActor static let beyondFold: CGPath = {
        let start = fold.currentPointOrigin
        let end = fold.currentPoint
        let path = CGMutablePath()
        path.addPath(fold)
        path.addLine(to: CGPoint(x: canvas, y: end.y))
        path.addLine(to: CGPoint(x: canvas, y: 0))
        path.addLine(to: CGPoint(x: start.x, y: 0))
        path.closeSubpath()
        return path
    }()

    /// The blue O: the O less its counter and less what has lifted away.
    @MainActor static let ring = outer.subtracting(counter, using: .evenOdd).subtracting(beyondFold, using: .evenOdd)

    /// The coral underside, beyond the fold and inside the flap's outline.
    @MainActor static let flap = flapCorner.subtracting(counter, using: .evenOdd)
        .intersection(beyondFold, using: .evenOdd)

    /// Where the curl's shadow falls: the flap moved down and to the left, to
    /// be blurred by ``curlShadowBlur`` and kept to the blue ring.
    @MainActor static let curlShadow: CGPath = {
        var offset = CGAffineTransform(translationX: -9 * scale, y: 10 * scale)
        return flap.copy(using: &offset) ?? flap
    }()

    /// The shadow's blur on the canvas, a standard deviation of 5 drawing units.
    static let curlShadowBlur: CGFloat = 5 * scale

    /// The least blur and the least fall, in points, the curl shadow keeps on
    /// a small mark, where the drawing's own would shrink below a pixel:
    /// enough for a 16-point mark to show its corner lifting.
    static let curlShadowMinimumBlur: CGFloat = 0.6
    static let curlShadowMinimumFall: CGFloat = 0.9

    /// How the flap moves as it lifts, from resting at 0 to fully lifted at 1:
    /// a few units up and toward its corner, turning a little about the middle
    /// of the fold.
    static func flapLift(_ lift: CGFloat) -> CGAffineTransform {
        guard lift != 0 else { return .identity }
        let pivot = CGPoint(x: 254, y: 116).applying(placement)
        return CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: -5 * .pi / 180 * lift)
            .translatedBy(x: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(translationX: 5 * scale * lift, y: -7 * scale * lift))
    }

    /// Where the curl's shadow falls from the flap lifted by `lift`: further
    /// away the higher it lifts. At rest it is ``curlShadow``'s offset.
    static func curlShadowOffset(_ lift: CGFloat) -> CGAffineTransform {
        let reach = 1 + 0.6 * lift
        return CGAffineTransform(translationX: -9 * scale * reach, y: 10 * scale * reach)
    }

    /// The curl shadow's blur, in points, on a mark drawn at `scale` points
    /// per canvas point with its flap lifted by `lift`: the drawing's own,
    /// scaled with the mark, and never under ``curlShadowMinimumBlur``.
    static func curlShadowBlur(scale: CGFloat, lift: CGFloat) -> CGFloat {
        max(curlShadowMinimumBlur, curlShadowBlur * scale * (1 + 0.5 * lift))
    }

    /// Where the curl's shadow falls on a mark drawn at `scale`, in canvas
    /// points: ``curlShadowOffset(_:)``, lengthened where it would fall less
    /// than ``curlShadowMinimumFall`` points.
    static func curlShadowOffset(_ lift: CGFloat, scale: CGFloat) -> CGAffineTransform {
        let offset = curlShadowOffset(lift)
        let fall = hypot(offset.tx, offset.ty) * scale
        guard fall > 0, fall < curlShadowMinimumFall else { return offset }
        let stretch = curlShadowMinimumFall / fall
        return CGAffineTransform(translationX: offset.tx * stretch, y: offset.ty * stretch)
    }

    /// The O and its flap together, the box a fitted mark fills.
    @MainActor static let bounds = ring.boundingBoxOfPath.union(flap.boundingBoxOfPath)

    /// For 32 points and below, where the fold's bends would blur: the O with
    /// a straight coral corner filled out to the flap's squarer outline. The
    /// cut crosses the O's top edge at x 590 and its right edge at y 446, about
    /// as much of the O as the flap takes.
    @MainActor static let smallCorner: CGPath = {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 327, y: 0), CGPoint(x: canvas, y: 0), CGPoint(x: canvas, y: 641)])
        path.closeSubpath()
        return path
    }()

    @MainActor static let smallRing = outer.subtracting(counter, using: .evenOdd).subtracting(
        smallCorner, using: .evenOdd)
    @MainActor static let smallFlap = flapCorner.subtracting(counter, using: .evenOdd)
        .intersection(smallCorner, using: .evenOdd)

    /// The side, in points, at and below which a mark is drawn small.
    static let smallSide: CGFloat = 32

    // MARK: - Types

    /// The superellipse exponent of each quarter of a shape; higher is squarer.
    struct Exponents {
        let topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat

        init(topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomRight = bottomRight
            self.bottomLeft = bottomLeft
        }

        init(uniform exponent: CGFloat) {
            self.init(topLeft: exponent, topRight: exponent, bottomRight: exponent, bottomLeft: exponent)
        }
    }

    // MARK: - Actions

    /// A closed shape whose four quarters are superellipses, each with its own
    /// radii and exponent, |x/a|^n + |y/b|^n = 1, meeting with matching
    /// tangents on the axes. Sampled finely enough to stay smooth at the icon's
    /// full size.
    static func quadrantShape(
        center: CGPoint, left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat,
        exponents: Exponents, samples: Int = 720
    ) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<samples {
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(samples)
            let cosine = cos(angle)
            let sine = sin(angle)
            let isRight = cosine >= 0
            let isBelow = sine >= 0
            let exponent =
                isRight
                ? (isBelow ? exponents.bottomRight : exponents.topRight)
                : (isBelow ? exponents.bottomLeft : exponents.topLeft)
            let point = CGPoint(
                x: center.x + (isRight ? right : left) * copysign(pow(abs(cosine), 2 / exponent), cosine),
                y: center.y + (isBelow ? bottom : top) * copysign(pow(abs(sine), 2 / exponent), sine))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func placed(_ path: CGPath) -> CGPath {
        var transform = placement
        return path.copy(using: &transform) ?? path
    }
}

extension CGPath {
    /// The point the path's first subpath starts from.
    fileprivate var currentPointOrigin: CGPoint {
        var origin = CGPoint.zero
        var found = false
        applyWithBlock { element in
            guard !found, element.pointee.type == .moveToPoint else { return }
            origin = element.pointee.points[0]
            found = true
        }
        return origin
    }
}
