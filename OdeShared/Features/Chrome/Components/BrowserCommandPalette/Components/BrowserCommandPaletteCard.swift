import SwiftUI

/// The palette's query field and results on the palette's surface.
///
/// An overlay card given a namespace and a resting width grows out of its
/// Space's sidebar address field and shrinks back into it. Its surface takes
/// the field's frame and corner radius and animates to its own, while the
/// contents keep their resting layout and show through the growing frame from
/// the top, so no text is squeezed on the way. The field hands over the shared
/// identity as the card arrives (``BrowserCommandPaletteHandoff``); where no
/// field holds it, the card simply appears where it rests.
struct BrowserCommandPaletteCard: View {
    // MARK: - Variables

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserCommandPaletteTransitionPhase) private var transitionPhase
    @Environment(\.browserChromeAppearance) private var chromeAppearance
    #if os(macOS)
        @Environment(BrowserGettingStartedTour.self) private var tour: BrowserGettingStartedTour?
        @Environment(BrowserGettingStartedMoves.self) private var moves: BrowserGettingStartedMoves?
        @Environment(\.browserNativeTabs) private var nativeTabs
    #endif

    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let maximumResultAreaHeight: CGFloat
    let morphNamespace: Namespace.ID?
    /// The width the card comes to rest at, which its contents keep while the
    /// card's frame morphs. Absent where the card never morphs.
    let restingWidth: CGFloat?
    let queryIsFocused: BrowserCommandPaletteFocusBinding

    /// How much taller than its minimum the input line has grown at a larger
    /// text size.
    @State private var fieldExcessHeight: CGFloat = 0
    @State private var tourCueHeight: CGFloat = 0
    /// How tall the provider chips' row is, which a larger text size makes
    /// taller than its least height.
    @State private var chipRowHeight = BrowserCommandPaletteMetrics.providerChipRowHeight

    /// Whether the card has arrived, rather than growing in or shrinking away.
    private var isSettled: Bool { transitionPhase.isIdentity }

    /// The edge the query row sits on, which shows first as the card grows.
    private var queryEdge: UnitPoint { presentation.listsUpward ? .bottom : .top }
    private var queryAlignment: Alignment { presentation.listsUpward ? .bottom : .top }

    /// The identity the card shares with its Space's address field.
    private var morph: BrowserCommandSurfaceMorph? {
        model.space.map { .commandPalette(spaceID: $0.id) }
    }

    // MARK: - Actions - Presentation

    var body: some View {
        surface
            .background { BrowserPlatformCommandPaletteScrollBoundary() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("command-palette")
    }

    @ViewBuilder
    private var surface: some View {
        if let morphNamespace, let morph, let restingWidth,
            BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
        {
            contents
                .frame(width: restingWidth)
                .animation(contentsAnimation) {
                    $0.opacity(isSettled ? 1 : 0)
                        .scaleEffect(
                            isSettled ? 1 : BrowserCommandPaletteMetrics.morphContentScale,
                            anchor: queryEdge
                        )
                }
                // Takes whatever frame the morph proposes. The resting
                // contents overflow it from the query row's edge.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: queryAlignment)
                .clipShape(morphingShape)
                .modifier(BrowserCommandPaletteShellMaterial(shape: morphingShape))
                .modifier(BrowserSearchProviderGlow(provider: model.activeProvider, shape: morphingShape))
                .animation(glassAnimation) {
                    $0.opacity(isSettled ? 1 : 0)
                }
                .matchedGeometryEffect(
                    id: morph,
                    in: morphNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: true
                )
                // At rest the card is exactly its contents' size; only the
                // morph proposes another.
                .fixedSize()
        } else {
            contents
                .frame(maxWidth: BrowserCommandPaletteMetrics.maximumCardWidth)
                .clipShape(restingShape)
                .modifier(BrowserCommandPaletteShellMaterial(shape: restingShape))
                .modifier(BrowserSearchProviderGlow(provider: model.activeProvider, shape: restingShape))
                // Appears where it rests: a fade, and with motion allowed a
                // slight settle toward its own center.
                .scaleEffect(
                    isSettled || reduceMotion ? 1 : BrowserCommandPaletteMetrics.inPlaceArrivalScale, anchor: .center
                )
                .opacity(isSettled ? 1 : 0)
        }
    }

    /// The field, the provider chips while what is typed names some, and the
    /// results, which a palette rising from the bottom of the screen lists
    /// above the field. The card is as tall as its rows; an overlay card's top
    /// stays put, so only its bottom edge moves as the results change.
    private var contents: some View {
        VStack(spacing: 0) {
            if presentation.listsUpward {
                if showsResults {
                    results
                }
                chips
                field
            } else {
                field
                chips
                // The query row's padding separates it from the results.
                if showsResults {
                    results
                }
            }
            tourCue
        }
    }

    @ViewBuilder
    private var tourCue: some View {
        #if os(macOS)
            if let tour, tour.isShowingGuide, tour.step == .answer || tour.step == .finished {
                VStack(spacing: OdeSpacing.small) {
                    Divider()
                    BrowserGettingStartedTourCue(
                        tour: tour, runCommand: { model.commands?.perform($0).wasPerformed == true },
                        compact: maximumResultAreaHeight < 260)
                    HStack {
                        Image(decorative: "OdeWelcomeBeret").resizable().scaledToFit().frame(height: 40)
                        Spacer()
                        Button("Skip tour") { tour.finishBrowsing(completed: false) }.buttonStyle(.odeSecondary)
                    }
                }
                .padding(OdeSpacing.medium)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    tourCueHeight = $0
                }
                .onDisappear { tourCueHeight = 0 }
            } else if let state = savedGuideState, let moves, state.chapter.showsMoves,
                let move = state.move ?? moves.next,
                let hint = move.paletteHint(
                    for: model.query, provider: model.activeProvider, offer: model.providerOffer,
                    example: BrowserGettingStartedGuideContext(browser: model.browser).keyword(for: move))
            {
                VStack(spacing: OdeSpacing.small) {
                    Divider()
                    HStack(spacing: OdeSpacing.medium) {
                        Text(hint)
                            .font(OdeTypography.sans(15))
                        Spacer(minLength: 0)
                        if let offer = model.providerOffer, move.accepts(offer) {
                            Button {
                                model.pressTab()
                            } label: {
                                BrowserGettingStartedTourKeycaps(keys: ["⇥"], confirmed: false, compact: true)
                            }
                            .buttonStyle(OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeRadius.control))
                            .accessibilityLabel("Enter search site")
                        }
                    }
                    if let consequence = move.consequence {
                        Text(consequence).font(OdeTypography.sans(12)).foregroundStyle(OdeBrandTheme.textSecondary)
                    }
                    HStack {
                        Image(decorative: "OdeWelcomeBeret").resizable().scaledToFit().frame(height: 32)
                        Spacer()
                        Button(moves.done.contains(move) ? "Next" : "Skip", systemImage: "arrow.right") {
                            state.move = moves.next(after: move)
                            model.dismiss()
                        }
                        .buttonStyle(.odeSecondary)
                    }
                }
                .padding(OdeSpacing.medium)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    tourCueHeight = $0
                }
                .onDisappear { tourCueHeight = 0 }
            }
        #endif
    }

    #if os(macOS)
        private var savedGuideState: BrowserGettingStartedState? {
            guard !model.browser.isPrivateBrowsing, let assignment = model.browser.shownTabAssignment,
                model.selectedTabID == assignment.tabID,
                model.browser.shownTab?.nativeTabContent == .gettingStarted,
                let runtime = nativeTabs?.runtime(matching: assignment, content: .gettingStarted)
            else { return nil }
            return runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        }
    #endif

    private var field: some View {
        BrowserCommandPaletteSearchField(
            model: model,
            presentation: presentation,
            queryIsFocused: queryIsFocused
        )
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            fieldExcessHeight = max(0, $0 - presentation.input.minimumHeight)
        }
    }

    @ViewBuilder
    private var chips: some View {
        if !model.providerChips.isEmpty {
            BrowserCommandPaletteProviderChips(model: model)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    chipRowHeight = $0
                }
        }
    }

    private var results: some View {
        BrowserCommandPaletteResultList(
            model: model,
            maximumResultAreaHeight: resultAreaHeight,
            listsUpward: presentation.listsUpward
        )
    }

    private var showsResults: Bool { !model.groups.isEmpty }

    /// The height the results may take, less what the provider chips take
    /// and what a larger text size adds to the input line of a field the card
    /// grows out of.
    private var resultAreaHeight: CGFloat {
        let chips = model.providerChips.isEmpty ? 0 : chipRowHeight
        let grownField = presentation.growsFromField ? fieldExcessHeight : 0
        return max(0, maximumResultAreaHeight - chips - grownField - tourCueHeight)
    }

    /// The card's own outline at rest, and the field's while the card is
    /// growing out of it or shrinking back, animated with the frame.
    private var morphingShape: RoundedRectangle {
        isSettled
            ? restingShape
            : RoundedRectangle(
                cornerRadius: BrowserDeviceAppearanceStore.shared.sidebarCornerRadius,
                style: .continuous
            )
    }

    private var restingShape: RoundedRectangle {
        // A card grown out of an address field takes the field's corner;
        // otherwise it follows the window's corner scale.
        RoundedRectangle(
            cornerRadius: presentation.growsFromField
                ? presentation.cornerRadius : chromeAppearance.cornerScale.surface,
            style: .continuous
        )
    }

    /// The contents appear once the frame has nearly settled, and clear
    /// before it starts to shrink.
    private var contentsAnimation: Animation? {
        let fade = isSettled ? BrowserCommandSurfaceMorph.trailingFade : BrowserCommandSurfaceMorph.leadingFade
        return fade.unlessReducingMotion(reduceMotion)
    }

    /// The glass takes over from the field as the frame leaves it, and hands
    /// back to the field as the frame lands on it.
    private var glassAnimation: Animation? {
        let fade = isSettled ? BrowserCommandSurfaceMorph.leadingFade : BrowserCommandSurfaceMorph.trailingFade
        return fade.unlessReducingMotion(reduceMotion)
    }
}
