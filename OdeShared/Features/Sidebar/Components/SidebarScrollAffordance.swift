import SwiftUI

extension View {
    /// Marks real rows, before the empty hit area expands to fill the viewport.
    func sidebarScrollContent() -> some View {
        modifier(SidebarScrollContentExtent())
    }
}

extension EnvironmentValues {
    @Entry fileprivate var sidebarScrollActivity: SidebarScrollActivity? = nil
}

private struct SidebarScrollContentExtent: ViewModifier {
    @Environment(\.sidebarScrollActivity) private var activity

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { height in
            activity?.contentHeight = height
        }
    }
}

/// The same vertical-scroll affordance in windowed and touch sidebars. Its
/// geometry updates are observed only by the indicator, never the tab rows.
///
/// Where the sidebar keeps the tab the window shows in view (`shownTabID`), it
/// scrolls that tab's row into view whenever the shown tab changes, the Space
/// comes on screen or the sidebar appears, except while the person scrolls or
/// drags in it or within a second of their last scroll. When the row is out of
/// view after all, a cue at the edge it is beyond scrolls back to it.
struct SidebarScrollAffordance: ViewModifier {
    // MARK: - Types

    private struct RevealRequest {
        let tabID: UUID
        let generation: Int
        let isAsked: Bool
        let lastPersonScroll: ContinuousClock.Instant?
    }

    // MARK: - Variables

    var isDragging = false
    /// Whether this sidebar keeps the shown tab in view.
    var revealsShownTab = false
    /// The tab the window shows in this sidebar's Space when its row is in
    /// this scrolling list, or nil.
    var shownTabID: UUID? = nil
    /// Where that tab's row falls among the list's rows, as a fraction from
    /// its top, for a row not laid out yet.
    var shownTabFraction: CGFloat? = nil
    /// Whether the list fades out toward its bottom edge while more of it
    /// lies below, where it ends against chrome rather than the window's edge.
    var fadesBottomEdge = false
    @State private var activity = SidebarScrollActivity()
    @State private var position = ScrollPosition()
    @State private var shownRows = SidebarShownRows()
    @State private var revealGeneration = 0
    @State private var revealTask: Task<Void, Never>?
    /// The original intent survives the estimated scroll; reporting geometry
    /// is not a new request from the person.
    @State private var landingRequest: RevealRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarSpaceIsSelected) private var isSelectedSpace

    private var landingFrame: CGRect? {
        landingRequest.flatMap { shownRows.frame(of: $0.tabID) }
    }

    // MARK: - Actions - Content

    func body(content: Content) -> some View {
        content
            .environment(\.sidebarScrollActivity, activity)
            .environment(\.sidebarShownRows, revealsShownTab ? shownRows : nil)
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: SidebarScrollMetrics.self) { geometry in
                SidebarScrollMetrics(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height + geometry.contentInsets.top
                        + geometry.contentInsets.bottom,
                    viewportHeight: geometry.containerSize.height,
                    visibleBottom: geometry.visibleRect.maxY)
            } action: { _, metrics in
                let previous = activity.lastPersonScroll
                activity.update(metrics)
                if previous != activity.lastPersonScroll { cancelReveal() }
            }
            .onScrollPhaseChange { _, phase in
                let previous = activity.lastPersonScroll
                activity.setScrolling(phase != .idle, byPerson: phase.isPersonDriven)
                if previous != activity.lastPersonScroll { cancelReveal() }
            }
            .onChange(of: position.isPositionedByUser) { _, byPerson in
                guard byPerson else { return }
                activity.personDidInteract()
                cancelReveal()
            }
            .modifier(SidebarScrollBottomFade(isEnabled: fadesBottomEdge, activity: activity, isDragging: isDragging))
            .overlay {
                SidebarScrollIndicator(
                    activity: activity, isDragging: isDragging,
                    currentTab: revealsShownTab ? shownTabID : nil, currentTabFraction: shownTabFraction,
                    shownRows: shownRows,
                    scrollDown: {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            position.scrollTo(
                                y: min(
                                    activity.metrics.maximumOffset,
                                    activity.metrics.offset + activity.metrics.viewportHeight * 0.85))
                        }
                    },
                    showCurrentTab: { reveal(animated: true, isAsked: true) })
            }
            .onAppear { reveal(animated: false) }
            .onChange(of: shownTabID) { reveal(animated: true) }
            .onChange(of: isSelectedSpace) { _, selected in
                if selected == false { cancelReveal() } else { reveal(animated: false) }
            }
            .onChange(of: revealsShownTab) { cancelReveal() }
            .onChange(of: isDragging) {
                activity.personDidInteract()
                cancelReveal()
            }
            .onChange(of: landingFrame) { _, frame in
                guard frame != nil, let request = landingRequest else { return }
                landingRequest = nil
                revealTask?.cancel()
                revealTask = Task { @MainActor in
                    defer { if request.generation == revealGeneration { revealTask = nil } }
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                    scroll(revealing: request, animated: true, estimatesPosition: false)
                }
            }
            .onDisappear {
                cancelReveal()
                activity.reset()
            }
    }

    // MARK: - Actions - Revealing

    /// Reveals only the selected Space's current row. An explicit cue click
    /// may bypass earlier scrolling and its quiet period, but later input
    /// invalidates either kind of request. A row not laid out yet is first
    /// approached by its logical position and lands once geometry arrives.
    private func reveal(animated: Bool, isAsked: Bool = false) {
        // Invalidate even when the new selection is nil or cannot reveal yet.
        cancelReveal()
        guard revealsShownTab, let tabID = shownTabID else { return }
        let request = RevealRequest(
            tabID: tabID, generation: revealGeneration, isAsked: isAsked,
            lastPersonScroll: activity.lastPersonScroll)
        guard mayReveal(request) else { return }
        revealTask = Task { @MainActor in
            defer { if request.generation == revealGeneration { revealTask = nil } }
            for _ in 0..<3 where shownRows.frame(of: tabID) == nil {
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            }
            scroll(revealing: request, animated: animated, estimatesPosition: true)
        }
    }

    private func mayReveal(_ request: RevealRequest) -> Bool {
        guard !Task.isCancelled, request.generation == revealGeneration,
            request.tabID == shownTabID, revealsShownTab, isSelectedSpace != false,
            request.lastPersonScroll == activity.lastPersonScroll
        else { return false }
        return request.isAsked
            || SidebarShownTabReveal.mayScroll(
                isScrolling: activity.isScrolling, isDragging: isDragging,
                lastPersonScroll: activity.lastPersonScroll, now: .now)
    }

    private func scroll(revealing request: RevealRequest, animated: Bool, estimatesPosition: Bool) {
        // No suspension may separate this ownership check from movement.
        guard mayReveal(request) else { return }
        let animation: Animation? = animated && !reduceMotion ? .easeInOut(duration: 0.25) : nil
        let metrics = activity.metrics
        if let row = shownRows.frame(of: request.tabID) {
            guard
                let target = SidebarShownTabReveal.offset(
                    revealing: row, offset: metrics.offset, viewportHeight: metrics.viewportHeight,
                    maximumOffset: metrics.maximumOffset)
            else { return }
            activity.beginProgrammaticScroll()
            withAnimation(animation) { position.scrollTo(y: target) }
        } else if estimatesPosition, let fraction = shownTabFraction {
            let middle = fraction * max(activity.contentHeight, metrics.contentHeight)
            let target = min(max(0, middle - metrics.viewportHeight / 2), metrics.maximumOffset)
            landingRequest = request
            activity.beginProgrammaticScroll()
            withAnimation(animation) { position.scrollTo(y: target) }
        }
    }

    private func cancelReveal() {
        revealGeneration &+= 1
        revealTask?.cancel()
        revealTask = nil
        landingRequest = nil
    }
}

extension ScrollPhase {
    /// Whether the person moves the list in this phase, rather than code.
    fileprivate var isPersonDriven: Bool {
        switch self {
        case .tracking, .interacting, .decelerating: true
        case .idle, .animating: false
        @unknown default: false
        }
    }
}

struct SidebarScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var visibleBottom: CGFloat = 0
    var maximumOffset: CGFloat { max(0, contentHeight - viewportHeight) }
}

/// Shows the indicator only while the list really moves. A scroll gesture
/// that begins over the list without moving it, such as a two-finger swipe
/// between Spaces whose first events reach the list before the pager claims
/// them, shows nothing; and neither does an offset the list's own resize
/// moves, as when a Space switch settles and the page takes its new height.
@MainActor
@Observable
final class SidebarScrollActivity {
    // MARK: - Static Variables

    /// How long after the viewport or content changes size an offset change
    /// still counts as part of that change.
    private static let layoutSettling: Duration = .milliseconds(300)

    /// How long a scroll the sidebar makes on its own keeps counting as its
    /// own, so the offsets it moves through are never taken for the person's.
    private static let programmaticScrolling: Duration = .milliseconds(600)

    // MARK: - Variables

    var contentHeight: CGFloat = 0
    var hasMoreBelow: Bool { metrics.viewportHeight > 0 && contentHeight > metrics.visibleBottom + 1 }
    private(set) var metrics = SidebarScrollMetrics()
    private(set) var showsIndicator = false
    /// Whether the sidebar is scrolling on its own to bring the shown tab in.
    private(set) var isRevealing = false
    @ObservationIgnored private(set) var isScrolling = false
    /// When the person last moved the list, by a gesture, a wheel or a drag.
    @ObservationIgnored private(set) var lastPersonScroll: ContinuousClock.Instant?
    @ObservationIgnored private var isPersonScrolling = false
    @ObservationIgnored private var programmaticUntil: ContinuousClock.Instant?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var resizedAt: ContinuousClock.Instant?

    // MARK: - Actions - Tracking

    func update(_ value: SidebarScrollMetrics) {
        let resized = value.viewportHeight != metrics.viewportHeight || value.contentHeight != metrics.contentHeight
        if resized { resizedAt = .now }
        let settling = resizedAt.map { ContinuousClock.now - $0 < Self.layoutSettling } ?? false
        let moved = abs(value.offset - metrics.offset) > 0.5 && !resized && (isScrolling || !settling)
        metrics = value
        // Discrete mouse wheels and programmatic drag autoscrolling may move
        // without a native gesture phase. They use the same idle deadline.
        if moved {
            showsIndicator = true
            if !isScrolling { scheduleIdle() }
            if programmaticUntil.map({ ContinuousClock.now >= $0 }) ?? true { personDidInteract() }
        }
    }

    /// The list started or stopped scrolling, `byPerson` while the person
    /// moves it. The moment a person's scroll ends counts as their last.
    func setScrolling(_ scrolling: Bool, byPerson: Bool = false) {
        if byPerson || isPersonScrolling { personDidInteract() }
        isPersonScrolling = scrolling && byPerson
        isScrolling = scrolling
        guard !scrolling else {
            idleTask?.cancel()
            return
        }
        if showsIndicator { scheduleIdle() }
    }

    /// Native input takes ownership even during a programmatic scroll's
    /// settling window, and a completed drag still invalidates pending work.
    func personDidInteract() {
        lastPersonScroll = .now
        programmaticUntil = nil
        revealTask?.cancel()
        revealTask = nil
        isRevealing = false
    }

    /// The sidebar starts a scroll of its own.
    func beginProgrammaticScroll() {
        isPersonScrolling = false
        programmaticUntil = .now + Self.programmaticScrolling
        isRevealing = true
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.programmaticScrolling) } catch { return }
            self?.isRevealing = false
        }
    }

    func reset() {
        idleTask?.cancel()
        idleTask = nil
        revealTask?.cancel()
        revealTask = nil
        isScrolling = false
        isPersonScrolling = false
        isRevealing = false
        showsIndicator = false
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            self?.showsIndicator = false
            self?.idleTask = nil
        }
    }
}

private struct SidebarScrollIndicator: View {
    // MARK: - Static Variables

    /// How far the bubble that scrolls on stands above the list's bottom edge.
    static let bubbleLift: CGFloat = 6
    static let bubbleDiameter = OdeLayout.glassIconButtonDiameter / 2

    // MARK: - Variables

    let activity: SidebarScrollActivity
    let isDragging: Bool
    /// The tab whose row the sidebar keeps in view, or nil.
    let currentTab: UUID?
    /// Where that row falls among the rows, for a row not laid out yet.
    let currentTabFraction: CGFloat?
    let shownRows: SidebarShownRows
    let scrollDown: () -> Void
    let showCurrentTab: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The edge the shown tab's row is beyond, while the person has it out of
    /// view and the sidebar is not bringing it back.
    private var currentTabEdge: SidebarShownTabReveal.Edge? {
        guard let currentTab, !isDragging, !activity.isRevealing else { return nil }
        let metrics = activity.metrics
        guard
            let row = shownRows.frame(of: currentTab)
                ?? currentTabFraction.map({
                    let middle = $0 * max(activity.contentHeight, metrics.contentHeight)
                    return CGRect(x: 0, y: middle - 20, width: 1, height: 40)
                })
        else { return nil }
        return SidebarShownTabReveal.edge(of: row, offset: metrics.offset, viewportHeight: metrics.viewportHeight)
    }

    private var showsBubble: Bool {
        activity.hasMoreBelow && !activity.showsIndicator && !isDragging && currentTabEdge != .bottom
    }

    var body: some View {
        GeometryReader { geometry in
            let track = max(0, geometry.size.height - 8)
            let metrics = activity.metrics
            let height = min(track, max(24, track * metrics.viewportHeight / max(1, metrics.contentHeight)))
            let fraction = min(1, max(0, metrics.offset / max(1, metrics.maximumOffset)))
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.primary.opacity(0.45))
                    .frame(width: 3, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 3)
                    .offset(y: 4 + (track - height) * fraction)
                    .opacity(activity.showsIndicator && metrics.maximumOffset > 1 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Button(action: scrollDown) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: Self.bubbleDiameter, height: Self.bubbleDiameter)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .frame(
                            width: OdeLayout.minimumHitTarget, height: OdeLayout.minimumHitTarget,
                            alignment: .bottom
                        )
                        // The bubble sits at the foot of its hit frame; the hit
                        // circle centers on the bubble, so a touch just below
                        // it scrolls rather than reaching the row behind.
                        .contentShape(
                            Circle().offset(y: (OdeLayout.minimumHitTarget - Self.bubbleDiameter) / 2)
                        )
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .scaleEffect(reduceMotion || showsBubble ? 1 : 0.5, anchor: .bottom)
                .offset(y: reduceMotion || showsBubble ? -Self.bubbleLift : OdeLayout.glassIconButtonDiameter + 8)
                .opacity(showsBubble ? 1 : 0)
                .allowsHitTesting(showsBubble)
                .accessibilityHidden(!showsBubble)
                .accessibilityLabel("Show more tabs")
                .accessibilityIdentifier("sidebar-more-tabs")
            }
            .overlay(alignment: currentTabEdge == .top ? .top : .bottom) {
                if let edge = currentTabEdge {
                    SidebarCurrentTabCue(edge: edge, action: showCurrentTab)
                        .padding(edge == .top ? .top : .bottom, OdeSpacing.small)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activity.showsIndicator)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsBubble)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentTabEdge)
            .clipped()
        }
    }
}

/// Fades the list out toward its bottom edge while more of it lies below, so
/// no row ends in the edge's cut and the bubble that scrolls on stands over
/// clear ground. While a row is dragged the list keeps every row in view.
private struct SidebarScrollBottomFade: ViewModifier {
    let isEnabled: Bool
    let activity: SidebarScrollActivity
    let isDragging: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.mask { SidebarScrollBottomFadeMask(activity: activity, isDragging: isDragging) }
        } else {
            content
        }
    }
}

/// The fade's mask, its own view so only it follows the scroll: opaque down
/// to a short fade, under which the bubble's footprint stays clear.
private struct SidebarScrollBottomFadeMask: View {
    let activity: SidebarScrollActivity
    let isDragging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fades: Bool { activity.hasMoreBelow && !isDragging }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: OdeSpacing.extraLarge)
                Color.clear.frame(height: SidebarScrollIndicator.bubbleLift + SidebarScrollIndicator.bubbleDiameter)
            }
            Color.black.opacity(fades ? 0 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: fades)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A quiet pointer at the edge of the sidebar beyond which the shown tab's
/// row lies, which scrolls back to it.
private struct SidebarCurrentTabCue: View {
    let edge: SidebarShownTabReveal.Edge
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Current tab", systemImage: edge == .top ? "arrow.up" : "arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, OdeSpacing.small)
                .padding(.vertical, OdeSpacing.extraSmall)
                .background { OdeSurfaceLayer(shape: Capsule(style: .continuous)) }
                .frame(minHeight: OdeLayout.minimumHitTarget)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Scroll to the current tab")
        .accessibilityLabel("Show current tab")
        .accessibilityIdentifier("sidebar-current-tab")
    }
}
