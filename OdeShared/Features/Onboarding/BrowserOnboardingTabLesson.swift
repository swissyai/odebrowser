import SwiftUI

/// Optional moments in a disposable browser. The host owns finishing setup;
/// neither finding an answer nor changing an example is required to continue.
struct BrowserOnboardingTabLesson: View {
    // MARK: - Types

    private enum Moment: Equatable { case commandBar, organization, room }

    // MARK: - Variables

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var practice: BrowserGettingStartedPractice
    @State private var moment = Moment.commandBar
    @State private var query = "23c in f"
    @State private var findQuery = ""
    @State private var quickAnswer: PaletteCard?
    @State private var foundTabs: [PaletteRow] = []
    @State private var failure: String?
    @State private var showsSidebar = true

    // MARK: - Initializers

    init(branding: SpaceBranding) {
        _practice = State(
            initialValue: BrowserGettingStartedPractice(spaces: [
                SpaceState.Seed(
                    name: String(localized: "Personal"), symbol: "sun.max", branding: branding,
                    tabs: [Self.tab(.trail), Self.tab(.packing)]),
                SpaceState.Seed(
                    name: String(localized: "Work"), symbol: "briefcase", accent: .orange,
                    branding: SpaceColorPreset.sand.branding,
                    tabs: [Self.tab(.mail), Self.tab(.reading, placement: .saved)]),
            ]))
    }

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            switch moment {
            case .commandBar: commandBar
            case .organization: organization
            case .room: room
            }
            if let failure {
                Text(failure).font(.callout).foregroundStyle(SpaceRoleStyle.dangerText)
            }
            navigation
        }
        .environment(practice.sidebarInteraction)
        .onChange(of: query, initial: true) { refreshAnswer() }
        .onChange(of: findQuery) { refreshTabs() }
        .onChange(of: practice.space.value) { refreshTabs() }
        .onDisappear { practice.sidebarInteraction.cancel() }
        .animation(OdeMotion.collection.unlessReducingMotion(reduceMotion), value: moment)
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            heading("Start with the Command Bar")
            Text(
                capabilities.supportsTouch
                    ? "Find tabs, search and get quick answers." : "⌘T finds tabs, searches and gives quick answers."
            )
            .font(.body).foregroundStyle(SpaceRoleStyle.secondaryText)
            VStack(alignment: .leading, spacing: OdeSpacing.large) {
                TextField("Try a calculation or conversion", text: $query)
                    .odeTextField()
                    .accessibilityLabel("Example Command Bar query")
                if let quickAnswer {
                    HStack(alignment: .top, spacing: OdeSpacing.medium) {
                        OdeMark(style: .mono).frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: OdeSpacing.small) {
                            Text(verbatim: quickAnswer.title)
                                .font(.title.weight(.semibold)).textSelection(.enabled)
                            Text(verbatim: quickAnswer.subtitle)
                                .font(.callout).foregroundStyle(SpaceRoleStyle.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Try 23c in f or 12 × 4.")
                        .font(.callout).foregroundStyle(SpaceRoleStyle.secondaryText)
                }
            }
            .padding(OdeSpacing.large)
            .background(OdeBrandTheme.surface, in: .rect(cornerRadius: OdeCornerScale.surface))
        }
    }

    private var organization: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            heading("Keep useful tabs together")
            Text("Save tabs you return to. Switch Spaces for a fresh set.")
                .font(.body).foregroundStyle(SpaceRoleStyle.secondaryText)
            spacePicker
            sidebar.frame(height: 240)
            if let trail = practice.tabID(.trail), practice.space.tabs.contains(trail) {
                if practice.space.tabs.model(trail)?.placement == .saved {
                    Label("Saved for next time", systemImage: "checkmark.circle")
                        .foregroundStyle(SpaceRoleStyle.accentText)
                } else {
                    BrowserGettingStartedSaveAction(
                        practice: practice, title: "Save A weekend away", systemImage: "bookmark", style: .odeSecondary)
                }
            }
            TextField("Find a tab", text: $findQuery)
                .odeTextField()
                .accessibilityLabel("Find an example tab")
            if !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if foundTabs.isEmpty {
                    Text("No matching tabs.").font(.callout).foregroundStyle(SpaceRoleStyle.secondaryText)
                }
                ForEach(foundTabs, id: \.tabID) { row in
                    Button {
                        select(row)
                    } label: {
                        Label(row.title, systemImage: "arrow.up.forward")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.odeSecondary)
                }
            }
        }
    }

    private var room: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            heading("Make room for the page")
            Text(
                capabilities.supportsTouch
                    ? "Keep your tabs nearby. Hide them when you want more room."
                    : "⌘S hides or shows the sidebar in Ode."
            )
            .font(.body).foregroundStyle(SpaceRoleStyle.secondaryText)
            HStack(spacing: 0) {
                if showsSidebar {
                    sidebar.frame(width: capabilities.supportsTouch ? 150 : 200)
                    Divider()
                }
                VStack(spacing: OdeSpacing.large) {
                    Image(systemName: "mountain.2").font(.system(size: 44, weight: .light))
                    Text(verbatim: practice.browser.shownTab?.shownTitle ?? String(localized: "Example page"))
                        .font(OdeTypography.display(26)).multilineTextAlignment(.center)
                }
                .padding(OdeSpacing.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OdeBrandTheme.surface)
            }
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: OdeCornerScale.surface))
            Button(showsSidebar ? "Hide sidebar" : "Show sidebar", systemImage: "sidebar.left") {
                showsSidebar.toggle()
            }
            .buttonStyle(.odeSecondary)
            .accessibilityHint("Changes only this example.")
        }
    }

    private var sidebar: some View {
        BrowserGettingStartedPracticeSidebar(
            practice: practice, capabilities: capabilities, showsHeader: false,
            backgroundBranding: practice.space.settings.look, showsEmptyPinnedSection: false
        )
        .id(practice.space.id)
        .clipShape(.rect(cornerRadius: OdeCornerScale.surface))
        .spaceColorRoles(for: practice.space.settings.look)
    }

    private var spacePicker: some View {
        OdeSpaceChipRail(
            spaces: OdeSpaceIdentity.list(practice.browser.workspaceModel?.spaces.models ?? []),
            selection: Binding(
                get: { practice.browser.selectedSpaceID },
                set: { if let id = $0 { practice.browser.selectSpace(id) } })
        )
        .accessibilityLabel("Example Spaces")
    }

    private var navigation: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: OdeSpacing.medium) { navigationButtons }
            VStack(alignment: .leading, spacing: OdeSpacing.small) { navigationButtons }
        }
    }

    @ViewBuilder private var navigationButtons: some View {
        if moment != .commandBar {
            Button("Previous") { moment = moment == .room ? .organization : .commandBar }
                .buttonStyle(.odeSecondary)
        }
        if moment != .room {
            Button("Continue", systemImage: "arrow.right") {
                moment = moment == .commandBar ? .organization : .room
            }
            .buttonStyle(.odeSecondary)
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title).font(OdeTypography.display(28)).accessibilityAddTraits(.isHeader)
    }

    // MARK: - Actions - Local examples

    private func refreshAnswer() {
        do {
            quickAnswer = try practice.answer(for: query).groups.flatMap(\.rows).compactMap(\.card)
                .first { $0.kind == .conversion || $0.kind == .calculation }
            failure = nil
        } catch {
            quickAnswer = nil
            failure = error.localizedDescription
        }
    }

    private func refreshTabs() {
        do {
            foundTabs = Array(
                try practice.answer(for: findQuery).groups.flatMap(\.rows).filter { row in
                    guard let id = row.tabID else { return false }
                    return practice.browser.workspaceModel?.spaces.models.contains { $0.tabs.contains(id) } == true
                }.prefix(3))
            failure = nil
        } catch {
            foundTabs = []
            failure = error.localizedDescription
        }
    }

    private func select(_ row: PaletteRow) {
        guard let id = row.tabID,
            let space = practice.browser.workspaceModel?.spaces.models.first(where: { $0.tabs.contains(id) })
        else { return }
        practice.browser.selectSpace(space.id)
        practice.browser.selectTab(id)
    }

    private static func tab(_ tab: PracticeTab, placement: TabPlacement = .current) -> TabState.Seed {
        TabState.Seed(title: tab.title, url: URL(string: tab.url), placement: placement, customTitle: tab.title)
    }
}
