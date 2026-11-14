import AppKit
import CoreGraphics
import SwiftUI
import XCTest

@testable import Ode

/// The sidebar keeps the shown tab in view without fighting the person: where
/// a row is revealed to, when the cue shows, and when the sidebar may move on
/// its own.
@MainActor
final class SidebarShownTabRevealTests: XCTestCase {
    private let viewport: CGFloat = 600
    private let rowHeight: CGFloat = 40

    private func row(at y: CGFloat) -> CGRect {
        CGRect(x: 0, y: y, width: 240, height: rowHeight)
    }

    func testARowBelowTheVisiblePartComesInAboveTheBottomEdgeWithRoomToSpare() throws {
        let target = try XCTUnwrap(
            SidebarShownTabReveal.offset(
                revealing: row(at: 1500), offset: 0, viewportHeight: viewport, maximumOffset: 4000))
        XCTAssertEqual(target + viewport - SidebarShownTabReveal.margin, 1500 + rowHeight)
    }

    func testARowAboveTheVisiblePartComesInBelowTheTopEdgeWithRoomToSpare() throws {
        let target = try XCTUnwrap(
            SidebarShownTabReveal.offset(
                revealing: row(at: 300), offset: 1200, viewportHeight: viewport, maximumOffset: 4000))
        XCTAssertEqual(target, 300 - SidebarShownTabReveal.margin)
    }

    func testARowInViewMovesNothingAndTheEndsOfTheListHoldTheScroll() {
        XCTAssertNil(
            SidebarShownTabReveal.offset(
                revealing: row(at: 100), offset: 0, viewportHeight: viewport, maximumOffset: 900))
        XCTAssertEqual(
            SidebarShownTabReveal.offset(
                revealing: row(at: 10), offset: 400, viewportHeight: viewport, maximumOffset: 900), 0)
        XCTAssertEqual(
            SidebarShownTabReveal.offset(
                revealing: row(at: 1460), offset: 0, viewportHeight: viewport, maximumOffset: 900), 900)
        let partly = row(at: 580)
        XCTAssertNotNil(
            SidebarShownTabReveal.offset(revealing: partly, offset: 0, viewportHeight: viewport, maximumOffset: 900),
            "A row cut by the edge comes in whole.")
    }

    func testTheCueShowsTheEdgeARowIsBeyondOnceLessThanHalfOfItShows() {
        XCTAssertEqual(SidebarShownTabReveal.edge(of: row(at: 700), offset: 0, viewportHeight: viewport), .bottom)
        XCTAssertEqual(SidebarShownTabReveal.edge(of: row(at: 100), offset: 600, viewportHeight: viewport), .top)
        XCTAssertEqual(SidebarShownTabReveal.edge(of: row(at: 585), offset: 0, viewportHeight: viewport), .bottom)
        XCTAssertNil(SidebarShownTabReveal.edge(of: row(at: 570), offset: 0, viewportHeight: viewport))
        XCTAssertNil(SidebarShownTabReveal.edge(of: row(at: 200), offset: 0, viewportHeight: viewport))
    }

    func testTheSidebarNeverMovesWhileThePersonScrollsOrDragsOrJustScrolled() {
        let now = ContinuousClock.now
        XCTAssertTrue(
            SidebarShownTabReveal.mayScroll(isScrolling: false, isDragging: false, lastPersonScroll: nil, now: now))
        XCTAssertFalse(
            SidebarShownTabReveal.mayScroll(isScrolling: true, isDragging: false, lastPersonScroll: nil, now: now))
        XCTAssertFalse(
            SidebarShownTabReveal.mayScroll(isScrolling: false, isDragging: true, lastPersonScroll: nil, now: now))
        XCTAssertFalse(
            SidebarShownTabReveal.mayScroll(
                isScrolling: false, isDragging: false, lastPersonScroll: now - .milliseconds(500), now: now))
        XCTAssertTrue(
            SidebarShownTabReveal.mayScroll(
                isScrolling: false, isDragging: false, lastPersonScroll: now - .milliseconds(1100), now: now))
    }

    func testThePersonsScrollsCountAndTheSidebarsOwnDoNot() throws {
        let activity = SidebarScrollActivity()
        activity.update(SidebarScrollMetrics(offset: 0, contentHeight: 3000, viewportHeight: 600, visibleBottom: 600))
        XCTAssertNil(activity.lastPersonScroll)
        awaitLayoutSettling()

        // The sidebar scrolls on its own: the offsets it moves through are its own.
        activity.beginProgrammaticScroll()
        XCTAssertTrue(activity.isRevealing)
        activity.update(
            SidebarScrollMetrics(offset: 400, contentHeight: 3000, viewportHeight: 600, visibleBottom: 1000))
        XCTAssertNil(activity.lastPersonScroll)

        // A gesture counts from its start to its end.
        activity.setScrolling(true, byPerson: true)
        let started = try XCTUnwrap(activity.lastPersonScroll)
        XCTAssertTrue(activity.isScrolling)
        activity.setScrolling(false)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(activity.lastPersonScroll), started)
        XCTAssertFalse(activity.isScrolling)
    }

    func testAWheelThatMovesTheListWithoutAGestureCountsAsThePersonsScroll() {
        let activity = SidebarScrollActivity()
        activity.update(SidebarScrollMetrics(offset: 0, contentHeight: 3000, viewportHeight: 600, visibleBottom: 600))
        awaitLayoutSettling()
        activity.update(SidebarScrollMetrics(offset: 80, contentHeight: 3000, viewportHeight: 600, visibleBottom: 680))
        XCTAssertNotNil(activity.lastPersonScroll)
    }

    func testARowNotLaidOutYetIsFoundByWhereItFallsAmongTheRows() throws {
        let tabs = (0..<4).map {
            TabState.Seed(title: "Tab \($0)", url: URL(string: "https://tab\($0).example/"), placement: .current)
        }
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = tabs
        let store = BrowserStore(seed: SessionState.Seed(spaces: [space], defaultSpaceID: space.id))
        let model = try XCTUnwrap(store.spaceModel(space.id))

        XCTAssertEqual(
            try XCTUnwrap(SidebarShownTabReveal.fraction(of: tabs[2].id, in: model)), 2.5 / 4, accuracy: 0.001)
        XCTAssertNil(SidebarShownTabReveal.fraction(of: UUID(), in: model))
    }

    func testARowReleasesItsRevealGeometryWhenItStopsShowingOrLeavesTheList() async throws {
        let rows = SidebarShownRows()
        let tabID = UUID()
        func content(shown: Bool, mounted: Bool = true) -> some View {
            VStack {
                if mounted {
                    Text("Page")
                        .sidebarShownRowReporting(tabID: tabID, isShown: shown)
                }
            }
            .environment(\.sidebarShownRows, rows)
        }
        let host = NSHostingView(rootView: content(shown: true))
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        func settle() async throws {
            host.layoutSubtreeIfNeeded()
            host.display()
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(100))
        }
        try await settle()
        XCTAssertNotNil(rows.frame(of: tabID))

        host.rootView = content(shown: false)
        try await settle()
        XCTAssertNil(rows.frame(of: tabID), "A former selection cannot leave a stale reveal destination")

        host.rootView = content(shown: true)
        try await settle()
        XCTAssertNotNil(rows.frame(of: tabID))
        host.rootView = content(shown: true, mounted: false)
        try await settle()
        XCTAssertNil(rows.frame(of: tabID), "An unloaded row must use its current logical position instead")
    }

    /// Waits out the moment after a resize in which an offset change still
    /// counts as part of the resize.
    private func awaitLayoutSettling() {
        let settled = expectation(description: "layout settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }
}

// Native input ownership, not appearance: delayed reveals must not reclaim a
// viewport after a person's input or a change of the window's selection.
@MainActor
final class SidebarDeferredRevealTests: XCTestCase {
    // MARK: - Actions - Ownership

    func testInitialGeometryWaitYieldsToNativeWheel() async throws {
        let fixture = try await makeFixture()
        defer { fixture.window.close() }
        fixture.model.selected = fixture.model.tabs[80]
        try await pause(20)
        fixture.model.phases = []
        try wheel(fixture.scroll)
        try await pause(30)
        let owned = fixture.scroll.contentView.bounds.minY
        XCTAssertGreaterThan(owned, 0)
        try await pause(700)
        XCTAssertGreaterThanOrEqual(fixture.scroll.contentView.bounds.minY, owned)
        assertNativeScrollKeptOwnership(fixture.model)
    }

    func testDelayedLandingYieldsToNativeWheel() async throws {
        let fixture = try await makeFixture()
        defer { fixture.window.close() }
        fixture.model.selected = fixture.model.tabs[80]
        try await pause(450)
        let fractional = fixture.scroll.contentView.bounds.minY
        XCTAssertGreaterThan(fractional, 400)
        fixture.model.reports = true
        try await pause(60)
        fixture.model.phases = []
        try wheel(fixture.scroll)
        try await pause(30)
        let owned = fixture.scroll.contentView.bounds.minY
        XCTAssertGreaterThan(owned, fractional + 1, "The native wheel must actually move the viewport")
        try await pause(800)
        XCTAssertGreaterThanOrEqual(fixture.scroll.contentView.bounds.minY, owned)
        assertNativeScrollKeptOwnership(fixture.model)
    }

    func testFinishedNativeDragInvalidatesPendingLanding() async throws {
        let fixture = try await makeFixture()
        let mouse = BrowserNativeMouseInput(window: fixture.window)
        defer { mouse.close() }
        fixture.model.selected = fixture.model.tabs[80]
        try await pause(450)
        fixture.model.reports = true
        try await pause(40)
        mouse.send(.leftMouseDown, at: CGPoint(x: 100, y: 150))
        mouse.send(.leftMouseDragged, at: CGPoint(x: 100, y: 190))
        XCTAssertTrue(fixture.model.dragging, "The input must reach SwiftUI's DragGesture")
        mouse.send(.leftMouseUp, at: CGPoint(x: 100, y: 190))
        XCTAssertFalse(fixture.model.dragging)
        let owned = fixture.scroll.contentView.bounds.minY
        try await pause(850)
        XCTAssertEqual(fixture.scroll.contentView.bounds.minY, owned, accuracy: 1)
    }

    func testExplicitCurrentTabCueStillWorksDuringTheScrollQuietPeriod() async throws {
        let fixture = try await makeFixture()
        let mouse = BrowserNativeMouseInput(window: fixture.window)
        defer { mouse.close() }
        fixture.model.selected = fixture.model.tabs[80]
        try await pause(450)
        fixture.model.reports = true
        try await pause(60)
        fixture.model.phases = []
        try wheel(fixture.scroll)
        try await pause(240)
        let owned = fixture.scroll.contentView.bounds.minY
        XCTAssertGreaterThan(owned, 1001, "The cue must be clicked after actual native scrolling")
        assertNativeScrollKeptOwnership(fixture.model)
        mouse.send(.leftMouseDown, at: CGPoint(x: 140, y: 370))
        mouse.send(.leftMouseUp, at: CGPoint(x: 140, y: 370))
        try await pause(700)
        XCTAssertGreaterThan(fixture.scroll.contentView.bounds.minY, owned + 1000)
        XCTAssertTrue(fixture.model.phases.contains(.animating), "The observer must see the cue's requested scroll")
    }

    func testInactiveSpaceAndLaterSelectionInvalidatePendingWork() async throws {
        for change in 0..<4 {
            let fixture = try await makeFixture()
            fixture.model.selected = fixture.model.tabs[80]
            try await pause(450)
            fixture.model.reports = true
            try await pause(50)
            if change == 0 { fixture.model.active = false }
            if change == 1 { fixture.model.selected = nil }
            if change == 2 {
                let beforeWheel = fixture.scroll.contentView.bounds.minY
                fixture.model.phases = []
                try wheel(fixture.scroll)
                try await pause(30)
                XCTAssertGreaterThan(
                    fixture.scroll.contentView.bounds.minY, beforeWheel + 1,
                    "Selection must change after actual native scrolling")
                fixture.model.selected = fixture.model.tabs[30]
            }
            if change == 3 {
                fixture.model.mounted = false
                try await pause(50)
                fixture.model.active = false
                fixture.model.mounted = true
            }
            let owned = fixture.scroll.contentView.bounds.minY
            try await pause(850)
            if change == 3 {
                let host = try XCTUnwrap(fixture.window.contentView)
                XCTAssertEqual(try XCTUnwrap(findScroll(in: host)).contentView.bounds.minY, 0, accuracy: 1)
            } else if change == 2 {
                XCTAssertGreaterThanOrEqual(fixture.scroll.contentView.bounds.minY, owned)
                assertNativeScrollKeptOwnership(fixture.model)
            } else {
                XCTAssertEqual(fixture.scroll.contentView.bounds.minY, owned, accuracy: 1)
            }
            fixture.window.close()
        }
    }

    // MARK: - Actions - Native Fixture

    private func assertNativeScrollKeptOwnership(
        _ model: DeferredRevealModel, file: StaticString = #filePath, line: UInt = #line
    ) {
        // Native deceleration may continue after the gesture ends. SwiftUI's
        // animating phase identifies a new programmatic scroll, not inertia.
        XCTAssertTrue(
            model.phases.contains(.interacting), "The native gesture must be observed", file: file, line: line)
        XCTAssertFalse(
            model.phases.contains(.animating), "Pending work reclaimed the person's viewport", file: file, line: line)
    }

    private func makeFixture() async throws -> (window: NSWindow, scroll: NSScrollView, model: DeferredRevealModel) {
        let model = DeferredRevealModel()
        let host = NSHostingView(
            rootView: DeferredRevealContent(model: model)
                .environment(\.accessibilityReduceMotion, false)
                .background(DeferredRevealEnvironmentProbe()))
        let window = DeferredRevealWindow(
            contentRect: CGRect(x: -40000, y: -40000, width: 280, height: 400),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        try await pause(450)
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertFalse(NSApplication.shared.isActive)
        XCTAssertTrue(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
        return (window, scroll, model)
    }

    private func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
    }

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func wheel(_ scroll: NSScrollView) throws {
        for (phase, delta): (CGScrollPhase, Int32) in [(.began, -1), (.changed, -89), (.ended, 0)] {
            let cgEvent = try XCTUnwrap(
                CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
            cgEvent.location = CGPoint(x: 140, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 200)
            cgEvent.timestamp = DispatchTime.now().uptimeNanoseconds
            cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
            NSApplication.shared.postEvent(event, atStart: true)
            let queued = try XCTUnwrap(
                NSApplication.shared.nextEvent(
                    matching: .scrollWheel, until: .distantPast, inMode: .default, dequeue: true))
            // A CG-backed event has no associated window. Deliver it to the
            // owning native scroll view; AppKit performs the actual movement.
            scroll.scrollWheel(with: queued)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }
}

@MainActor
private final class DeferredRevealWindow: NSWindow {
    // MARK: - Variables

    // Native gesture scrolling needs a display clock even when the fixture
    // stays physically offscreen. No frame, pointer or activation is changed.
    override var screen: NSScreen? { NSScreen.screens.first }
}

@MainActor
@Observable
private final class DeferredRevealModel {
    // MARK: - Variables

    let tabs = (0..<100).map { _ in UUID() }
    var selected: UUID?
    var reports = false
    var dragging = false
    var active = true
    var mounted = true
    var phases: [ScrollPhase] = []
}

// Temporary CI probe reads both inherited and fixture-effective values without changing system settings.
private struct DeferredRevealEnvironmentProbe: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear.onAppear {
            guard ProcessInfo.processInfo.environment["ODE_NATIVE_CI_DIAGNOSTICS"] == "1" else { return }
            print("ODE_NATIVE_CI sidebar phase=inherited-environment reduceMotion=\(reduceMotion)")
        }
    }
}

private struct DeferredRevealContent: View {
    // MARK: - Variables

    let model: DeferredRevealModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Content

    var body: some View {
        VStack {
            if model.mounted {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.tabs, id: \.self) { tab in
                            Text(tab == model.selected ? "Current page" : "Page")
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .contentShape(.rect)
                                .gesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { _ in model.dragging = true }
                                        .onEnded { _ in model.dragging = false }
                                )
                                .sidebarShownRowReporting(
                                    tabID: tab, isShown: model.reports && tab == model.selected)
                        }
                    }
                    .sidebarScrollContent()
                    .coordinateSpace(.named(SidebarShownTabReveal.contentSpace))
                }
                .modifier(
                    SidebarScrollAffordance(
                        isDragging: model.dragging, revealsShownTab: true,
                        shownTabID: model.selected, shownTabFraction: 0.3)
                )
                .onScrollPhaseChange { _, phase in model.phases.append(phase) }
                .environment(\.sidebarSpaceIsSelected, model.active)
            }
        }
        .onAppear {
            guard ProcessInfo.processInfo.environment["ODE_NATIVE_CI_DIAGNOSTICS"] == "1" else { return }
            print("ODE_NATIVE_CI sidebar phase=fixture-environment reduceMotion=\(reduceMotion)")
        }
    }
}
