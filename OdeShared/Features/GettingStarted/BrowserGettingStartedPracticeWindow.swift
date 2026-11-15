#if os(macOS)
    import SwiftUI

    struct BrowserGettingStartedPracticeWindow: View {
        @Bindable var practice: BrowserGettingStartedPractice
        let showsSplit: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.browserChromeAppearance) private var chromeAppearance

        private static let windowButtonColors: [Color] = [
            Color(red: 1, green: 0.373, blue: 0.341), Color(red: 0.996, green: 0.737, blue: 0.180),
            Color(red: 0.157, green: 0.784, blue: 0.251),
        ]

        private var capabilities: BrowserInteractionCapabilities {
            BrowserInteractionCapabilities(
                supportsHover: true, supportsTouch: false, pairsRowWithPromotedSurface: false)
        }

        var body: some View {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        // The Mac's own close, minimize and zoom colors, so the
                        // practice reads as a window.
                        ForEach(Self.windowButtonColors, id: \.self) { color in
                            Circle().fill(color).frame(width: 12, height: 12)
                        }
                        Spacer()
                        Label("Practice window", systemImage: "leaf").font(OdeTypography.sans(11, weight: .medium))
                        Spacer()
                        Text("Ode").font(OdeTypography.sans(10, weight: .semibold)).foregroundStyle(.secondary)
                    }.padding(14)
                    Divider()
                    if showsSplit {
                        splitPages
                    } else {
                        HStack(spacing: 0) {
                            sidebar.frame(width: geometry.size.width >= 620 ? 285 : nil)
                            if geometry.size.width >= 620 {
                                Divider()
                                documentArea
                            }
                        }
                    }
                }
                .background(OdeBrandTheme.canvas)
                .clipShape(.rect(cornerRadius: chromeAppearance.cornerScale.surface, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: chromeAppearance.cornerScale.surface, style: .continuous)
                        .strokeBorder(OdeBrandTheme.line)
                )
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                #if os(macOS)
                    .background { liftPreview }
                #endif
            }
            .onChange(of: practice.members.map(\.id), initial: true) { _, _ in
                practice.reconcileSplitWidths()
            }
            .animation(reduceMotion ? nil : OdeMotion.collection, value: practice.space.sidebar.lists.map(\.rows))
        }

        private var sidebar: some View {
            BrowserGettingStartedPracticeSidebar(practice: practice, capabilities: capabilities)
        }

        // The miniature teaches choosing and moving real practice members;
        // full browser card minima would clip a page in this smaller viewport.
        private var splitPages: some View {
            HStack(spacing: OdeSpacing.small) {
                ForEach(practice.members) { tab in
                    BrowserRootContentSurface(
                        cornerRadius: chromeAppearance.framedPageCornerRadius,
                        frameInsets: EdgeInsets(), usesTransparentInnerSurface: false
                    ) {
                        practiceDocument(tab)
                            .contentShape(.rect)
                            .onTapGesture { practice.browser.selectTab(tab.id) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if practice.members.count > 1 {
                            BrowserSplitCardFocusIndicator(
                                isFocused: tab.id == practice.selectedTabID, accent: OdeBrandPalette.coral,
                                cornerRadius: chromeAppearance.framedPageCornerRadius)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityAction(named: "Focus This Split View Card") { practice.browser.selectTab(tab.id) }
                }
            }
            .padding(10)
            .background(OdeBrandTheme.surface)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Split View practice pages")
        }

        private var documentArea: some View {
            let members = practice.members
            return Group {
                if members.isEmpty {
                    ContentUnavailableView(
                        "Open tabs cleared", systemImage: "sun.max",
                        description: Text("Your pinned and saved tabs are still in the sidebar."))
                } else {
                    BrowserSplitColumnsView(
                        members: members, focusedTabID: practice.selectedTabID,
                        frameInsets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
                        accent: OdeBrandPalette.coral,
                        placeholderIndex: nil, liftedTabID: nil, widthTransaction: $practice.splitWidths,
                        onResizeCommit: { _ in }, onFocus: practice.browser.selectTab,
                        usesTransparentInnerSurface: { _ in false }
                    ) { tab, _ in
                        practiceDocument(tab)
                            .contentShape(.rect)
                            .onTapGesture { practice.browser.selectTab(tab.id) }
                            .browserSplitDropCardFrame(
                                tabID: tab.id, assignment: practice.assignment,
                                state: practice.sidebarInteraction.sidebarReorderState)
                    }
                }
            }.background(OdeBrandTheme.surface)
                .browserSplitContentDropZone(
                    assignment: practice.assignment, state: practice.sidebarInteraction.sidebarReorderState)
        }

        private func practiceDocument(_ tab: TabStateModel) -> some View {
            VStack(alignment: .leading, spacing: showsSplit ? 8 : 16) {
                HStack {
                    TabStateFaviconView(
                        tab: tab, favicons: practice.browser.core.state.favicons, profileID: practice.space.profileID,
                        size: 18)
                    Text(tab.shownTitle).font(OdeTypography.sans(12, weight: .semibold)).lineLimit(1)
                }
                Divider()
                Spacer(minLength: 0)
                if tab.id == practice.tabID(.packing) || tab.title == PracticeTab.packing.title {
                    Text("Packing list").font(OdeTypography.display(showsSplit ? 20 : 27))
                    ForEach(["Walking shoes", "Water bottle", "Trail map"], id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle").font(OdeTypography.sans(12)).foregroundStyle(
                            .secondary)
                    }
                } else {
                    Image(systemName: "mountain.2").font(.system(size: showsSplit ? 32 : 54, weight: .ultraLight))
                        .foregroundStyle(
                            OdeBrandPalette.sage)
                    Text("Weekend trail guide").font(OdeTypography.display(showsSplit ? 20 : 30))
                    Text("Distance: 4.2 miles\nDuration: 2 hours\nRoute: lakeside loop")
                        .font(OdeTypography.sans(13)).foregroundStyle(.secondary).fixedSize(
                            horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !showsSplit {
                    Text("Example page").font(OdeTypography.sans(11, weight: .medium)).foregroundStyle(.tertiary)
                }
            }
            .padding(showsSplit ? 12 : 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(OdeBrandTheme.canvas)
        }

        #if os(macOS)
            private var liftPreview: some View {
                let state = practice.sidebarInteraction.sidebarReorderState
                return BrowserDragPreviewWindowBridge(
                    content: liftContent,
                    onSidebarLandingComplete: state.finishLanding, onSidebarLandingArrived: state.revealLanding
                )
                .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            }

            private var liftContent: BrowserDragPreviewWindowContent? {
                guard let lift = practice.sidebarInteraction.sidebarReorderState.liftPreview,
                    let space = practice.browser.workspaceModel?.spaces.models.first
                else { return nil }
                guard let subject = lift.item.liftPreviewSubject(in: space, previewRows: []) else { return nil }
                return .sidebarLift(
                    BrowserSidebarLiftPreviewContent(
                        subject: subject, favicons: practice.browser.core.state.favicons, lift: lift,
                        reduceMotion: reduceMotion, selectedTabID: practice.selectedTabID,
                        loadedTabIDs: Set(space.tabs.models.map(\.id))))
            }
        #endif
    }

#endif
