import SwiftUI

/// The stage setup's import plays on while it runs: the browser's icon on
/// the left, Ode's sidebar on the right, and one line under it. The first
/// Space's pinned and saved icons fly from the browser into their places,
/// the sidebar takes the Space's color, the rest of its rows appear, and the
/// next Spaces slide in as a Space swipe does. A click or a key jumps to the
/// end; with Reduce Motion each Space takes its color and rows in one fade.
struct BrowserOnboardingImportStageView: View {
    let stage: BrowserOnboardingImportStage
    /// Draws the stage still at this many seconds in, for a snapshot.
    var frozenTime: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var beatsEnded = false
    @FocusState private var isFocused: Bool

    private var choreography: BrowserOnboardingImportChoreography {
        BrowserOnboardingImportChoreography(
            flightCount: stage.shownSpaces.first?.flights.count ?? 0,
            spaceCount: stage.spaces.count,
            reducesMotion: reduceMotion)
    }

    var body: some View {
        let choreography = choreography
        TimelineView(.animation(minimumInterval: nil, paused: beatsEnded || stage.isSkipped || frozenTime != nil)) {
            context in
            let time =
                frozenTime
                ?? (beatsEnded || stage.isSkipped
                    ? choreography.end : context.date.timeIntervalSince(stage.startedAt))
            BrowserOnboardingImportStageFrame(
                stage: stage, choreography: choreography, time: time,
                increasesContrast: contrast == .increased)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(.rect)
        .onTapGesture { stage.skip() }
        .odeControlPointer()
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress { _ in
            stage.skip()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Importing from \(stage.sourceTitle)"))
        .task {
            isFocused = true
            try? await Task.sleep(for: .seconds(choreography.end + 0.05))
            beatsEnded = true
        }
    }
}

/// One frame of the stage at `time` seconds from its start.
private struct BrowserOnboardingImportStageFrame: View {
    let stage: BrowserOnboardingImportStage
    let choreography: BrowserOnboardingImportChoreography
    let time: TimeInterval
    let increasesContrast: Bool

    private static let sidebarSize = CGSize(width: 300, height: 400)
    private static let sourceIconSize: CGFloat = 64
    /// How far above the straight line a flying icon's path bows.
    private static let flightLift: CGFloat = 40

    var body: some View {
        let settle = eased(.easeOut, progress(start: 0, duration: choreography.settled))
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 96) {
                sourceIcon
                    .offset(x: -12 * (1 - settle))
                sidebar
                    .offset(x: 12 * (1 - settle))
            }
            .opacity(settle)
            BrowserOnboardingImportStageStatus(stage: stage, increasesContrast: increasesContrast)
                .opacity(settle)
            Spacer(minLength: 0)
        }
        .padding(32)
        .overlayPreferenceValue(BrowserOnboardingImportAnchorKey.self) { anchors in
            GeometryReader { proxy in
                flights(anchors: anchors, in: proxy)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Parts

    private var sourceIcon: some View {
        let leaving = stage.isDone ? eased(.easeIn, progress(start: choreography.end - 0.18, duration: 0.18)) : 0
        return Group {
            if let icon = stage.sourceIcon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.sourceIconSize, height: Self.sourceIconSize)
        .anchorPreference(key: BrowserOnboardingImportAnchorKey.self, value: .center) {
            [BrowserOnboardingImportAnchorKey.source: $0]
        }
        .scaleEffect(1 - 0.06 * leaving)
        .opacity(1 - leaving)
        .accessibilityLabel(Text(stage.sourceTitle))
    }

    /// Ode's sidebar, neutral until the first Space takes its color, then
    /// each shown Space in turn.
    private var sidebar: some View {
        let spaces = Array(stage.shownSpaces.prefix(choreography.spaceCount))
        let current = spaces.indices.last { choreography.spaceStart($0) <= time } ?? 0
        return ZStack {
            BrowserImportSidebarFrame(branding: .neutral) { Color.clear }
            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                if index == current || index == current - 1 {
                    spacePage(space, index: index, current: current)
                }
            }
        }
        .frame(width: Self.sidebarSize.width, height: Self.sidebarSize.height)
        .clipShape(.rect(cornerRadius: OdeCornerScale.surface, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private func spacePage(_ space: BrowserOnboardingImportStage.Space, index: Int, current: Int) -> some View {
        let isFirst = index == 0
        let arrival = isFirst ? 1 : swipe(progress(start: choreography.spaceStart(index), duration: swipeDuration))
        let departure =
            index == current - 1
            ? swipe(progress(start: choreography.spaceStart(current), duration: swipeDuration)) : 0
        let color =
            isFirst
            ? eased(
                .easeInOut,
                progress(
                    start: choreography.reducesMotion ? choreography.settled : choreography.firstLanding,
                    duration: choreography.reducesMotion
                        ? BrowserOnboardingImportChoreography.reducedFade
                        : BrowserOnboardingImportChoreography.takeColor)) : 1
        // The next Space pushes the last one out as a Space swipe does; with
        // Reduce Motion one fades out before the other fades in.
        let slide: CGFloat = choreography.reducesMotion ? 0 : Self.sidebarSize.width
        let look = space.space.settings.look
        // The Space's ground fades over the neutral one while its rows stay
        // put, so an icon that lands is never hidden by the color coming in.
        return ZStack {
            BrowserImportSidebarFrame(branding: look) { Color.clear }
                .opacity(color)
            BrowserOnboardingImportStageSidebar(
                space: space, favicons: stage.favicons,
                showsName: isFirst ? nameProgress : 1,
                showsRest: isFirst ? restProgress : 1,
                landed: { tabID in isFirst ? hasLanded(tabID, in: space) : true }
            )
            .spaceColorRoles(for: look)
            .environment(\.colorScheme, look.foregroundTone.colorScheme)
        }
        .opacity(
            choreography.reducesMotion
                ? min(max(arrival * 2 - 1, 0), 1) * min(max(1 - departure * 2, 0), 1) : 1
        )
        .offset(x: slide * (1 - arrival) - slide * departure)
    }

    private func flights(
        anchors: [String: Anchor<CGPoint>], in proxy: GeometryProxy
    ) -> some View {
        let space = stage.shownSpaces.first
        let source = anchors[BrowserOnboardingImportAnchorKey.source].map { proxy[$0] }
        return ZStack(alignment: .topLeading) {
            if let space, let source, !choreography.reducesMotion {
                ForEach(Array(space.flights.enumerated()), id: \.element.id) { index, tab in
                    let flight = progress(
                        start: choreography.flightStart(index), duration: BrowserOnboardingImportChoreography.flight)
                    if flight > 0, flight < 1, let slot = anchors[tab.id.uuidString].map({ proxy[$0] }) {
                        let travel = Self.flightCurve.value(at: flight)
                        TabStateFaviconView(
                            tab: tab, favicons: stage.favicons, profileID: space.space.profileID, size: 22
                        )
                        .scaleEffect(0.92 + 0.08 * travel)
                        .opacity(
                            min(
                                1,
                                flight * BrowserOnboardingImportChoreography.flight
                                    / BrowserOnboardingImportChoreography.flightFadeIn)
                        )
                        .position(Self.point(on: source, slot, at: travel))
                    }
                }
            }
        }
    }

    // MARK: - Timing

    private var nameProgress: Double {
        choreography.reducesMotion
            ? progress(start: choreography.settled, duration: BrowserOnboardingImportChoreography.reducedFade)
            : progress(start: choreography.firstLanding, duration: BrowserOnboardingImportChoreography.nameFade)
    }

    private var restProgress: Double {
        choreography.reducesMotion
            ? progress(start: choreography.settled, duration: BrowserOnboardingImportChoreography.reducedFade)
            : eased(
                .easeOut, progress(start: choreography.lastLanding, duration: BrowserOnboardingImportChoreography.rest))
    }

    private var swipeDuration: TimeInterval {
        choreography.reducesMotion
            ? BrowserOnboardingImportChoreography.reducedFade : BrowserOnboardingImportChoreography.nextSpace
    }

    private func hasLanded(_ tabID: UUID, in space: BrowserOnboardingImportStage.Space) -> Bool {
        guard !choreography.reducesMotion, let index = space.flights.firstIndex(where: { $0.id == tabID }) else {
            return restProgress >= 1
        }
        return time >= choreography.flightStart(index) + BrowserOnboardingImportChoreography.flight
    }

    private func progress(start: TimeInterval, duration: TimeInterval) -> Double {
        BrowserOnboardingImportChoreography.progress(at: time, start: start, duration: duration)
    }

    private func swipe(_ value: Double) -> Double {
        eased(.easeInOut, value)
    }

    private func eased(_ curve: UnitCurve, _ value: Double) -> Double {
        curve.value(at: value)
    }

    /// The flight's ease: quick to leave, gentle to land.
    private static let flightCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1))

    /// A point along the shallow arc from `start` to `end`.
    private static func point(on start: CGPoint, _ end: CGPoint, at t: Double) -> CGPoint {
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - flightLift)
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }
}

/// The line under the stage: what the import is doing, or what came over,
/// and, once done, what it left out.
private struct BrowserOnboardingImportStageStatus: View {
    let stage: BrowserOnboardingImportStage
    let increasesContrast: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 6) {
                Text(verbatim: stage.statusLine(at: context.date))
                    .font(OdeTypography.sans(15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(OdeMotion.collection, value: stage.statusLine(at: context.date))
                if stage.isDone {
                    ForEach(stage.shownSpaces) { space in
                        Text(verbatim: space.countLine)
                            .font(OdeTypography.sans(13).monospacedDigit())
                            .foregroundStyle(increasesContrast ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
                if stage.isDone, let leftOut = stage.leftOutLine {
                    Text(verbatim: leftOut)
                        .font(OdeTypography.sans(12))
                        .foregroundStyle(increasesContrast ? .primary : .secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Where the source browser's icon and each tab's place in the sidebar sit,
/// so a flying icon knows where it starts and lands.
struct BrowserOnboardingImportAnchorKey: PreferenceKey {
    static let source = "source"
    static let defaultValue: [String: Anchor<CGPoint>] = [:]

    static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}
