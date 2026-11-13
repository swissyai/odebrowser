import CoreGraphics
import XCTest

@testable import Ode

final class OdeCornerScaleTests: XCTestCase {
    func testCornerScaleNestsFromTheWindowCorner() {
        let tahoe = OdeCornerScale(window: 26)
        XCTAssertEqual([tahoe.surface, tahoe.row, tahoe.inset], [18, 10, 6])
        let smaller = OdeCornerScale(window: 20)
        XCTAssertEqual([smaller.surface, smaller.row, smaller.inset], [12, 8, 6])
        let fullScreen = OdeCornerScale(window: nil)
        XCTAssertEqual([fullScreen.surface, fullScreen.row, fullScreen.inset], [14, 8, 6])
    }

    func testTheCommandBarAndFloatingSidebarFollowTheWindow() {
        let appearance = BrowserChromeAppearance(windowCornerRadius: 26)
        XCTAssertEqual(appearance.cornerScale.surface, 18)
        XCTAssertEqual(BrowserSidebarPresentation.floatingCardInset, OdeCornerScale.gutter)
        XCTAssertEqual(BrowserChromeLayout.pageCornerRadius, 14)
        XCTAssertEqual(OdeRadius.control, 8)
    }
}

@MainActor
final class OdeMarkDipTests: XCTestCase {
    func testTheDipPlaysOncePerSession() {
        let dip = OdeMarkDip()
        XCTAssertTrue(dip.claim(reduceMotion: false, isActive: true, lowPower: false))
        XCTAssertFalse(dip.claim(reduceMotion: false, isActive: true, lowPower: false))
    }

    func testReduceMotionLowPowerAndAnInactiveWindowSkipTheDipWithoutUsingIt() {
        let dip = OdeMarkDip()
        XCTAssertFalse(dip.claim(reduceMotion: true, isActive: true, lowPower: false))
        XCTAssertFalse(dip.claim(reduceMotion: false, isActive: true, lowPower: true))
        XCTAssertFalse(dip.claim(reduceMotion: false, isActive: false, lowPower: false))
        XCTAssertTrue(dip.claim(reduceMotion: false, isActive: true, lowPower: false))
    }

    func testAFlapAtRestDrawsTheMarkUnchanged() {
        XCTAssertEqual(OdeMarkGeometry.flapLift(0), .identity)
        let resting = OdeMarkGeometry.flap.copy(using: [OdeMarkGeometry.curlShadowOffset(0)])
        XCTAssertEqual(resting?.boundingBoxOfPath, OdeMarkGeometry.curlShadow.boundingBoxOfPath)
    }

    func testALiftedFlapRisesTowardItsCornerAndItsShadowFallsFurther() {
        let resting = OdeMarkGeometry.flap.boundingBoxOfPath
        let lifted = resting.applying(OdeMarkGeometry.flapLift(1))
        XCTAssertGreaterThan(lifted.midX, resting.midX)
        XCTAssertLessThan(lifted.midY, resting.midY)
        XCTAssertGreaterThan(OdeMarkGeometry.curlShadowOffset(1).ty, OdeMarkGeometry.curlShadowOffset(0).ty)
    }

    func testTheCurlShadowScalesWithTheMarkAndKeepsAFloorSoA16PointMarkStillShowsIt() {
        let scale = { (side: CGFloat) in
            side / max(OdeMarkGeometry.bounds.width, OdeMarkGeometry.bounds.height)
        }
        let fall = { (side: CGFloat) in
            let offset = OdeMarkGeometry.curlShadowOffset(0, scale: scale(side))
            return hypot(offset.tx, offset.ty) * scale(side)
        }
        for side: CGFloat in [16, 32] {
            XCTAssertEqual(
                OdeMarkGeometry.curlShadowBlur(scale: scale(side), lift: 0), OdeMarkGeometry.curlShadowMinimumBlur)
            XCTAssertGreaterThanOrEqual(fall(side), OdeMarkGeometry.curlShadowMinimumFall - 0.001)
        }
        // Large marks keep the drawing's own shadow, scaled.
        XCTAssertEqual(
            OdeMarkGeometry.curlShadowBlur(scale: scale(256), lift: 0),
            OdeMarkGeometry.curlShadowBlur * scale(256), accuracy: 0.001)
        XCTAssertEqual(OdeMarkGeometry.curlShadowOffset(0, scale: scale(256)), OdeMarkGeometry.curlShadowOffset(0))
        XCTAssertGreaterThan(fall(256), fall(64))
        XCTAssertEqual(OdeMark().finish, .curlShadow)
    }
}

extension CGPath {
    fileprivate func copy(using transforms: [CGAffineTransform]) -> CGPath? {
        var transform = transforms.reduce(CGAffineTransform.identity) { $0.concatenating($1) }
        return copy(using: &transform)
    }
}

final class OdeFloatingSurfaceCornerTests: XCTestCase {
    /// Peek floats in a window and takes a surface's corner of it, as every
    /// floating surface does; only the touch sheet keeps its own.
    func testPeekTakesASurfacesCornerOfItsWindow() {
        for arrangement in [BrowserTransientCardArrangement.pointer, .canvas] {
            XCTAssertEqual(arrangement.cornerRadius(in: OdeCornerScale(window: 26)), 18)
            XCTAssertEqual(arrangement.cornerRadius(in: OdeCornerScale(window: nil)), 14)
        }
        XCTAssertEqual(BrowserTransientCardArrangement.sheet.cornerRadius(in: OdeCornerScale(window: 26)), 24)
    }

    /// A page's host clips at the layer, which reaches a platform view and
    /// the remote layer Chromium draws into.
    @MainActor
    func testAPageHostClipsItsPageAtTheLayer() throws {
        let host = BrowserWebHostView()
        host.updateCornerRadius(18)
        let layer = try XCTUnwrap(host.layer)
        XCTAssertEqual(layer.cornerRadius, 18)
        XCTAssertTrue(layer.masksToBounds)
        XCTAssertEqual(layer.cornerCurve, .continuous)
        XCTAssertEqual(host.clippedCornerRadius, 18)

        host.updateCornerRadius(nil)
        XCTAssertFalse(layer.masksToBounds)
        XCTAssertNil(host.clippedCornerRadius)
    }
}
