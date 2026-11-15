#if os(macOS)
    import SwiftUI

    struct BrowserGettingStartedView: View {
        let openURL: (URL) -> Void
        let browse: () -> Void
        let guideContext: () -> BrowserGettingStartedGuideContext?
        let openSearchSettings: () -> Bool
        @Bindable var state: BrowserGettingStartedState
        private var practice: BrowserGettingStartedPractice { state.practice }
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(BrowserGettingStartedMoves.self) private var moves: BrowserGettingStartedMoves?
        @Environment(\.browserNativeTabActions) private var actions
        @Environment(BrowserGettingStartedTour.self) private var tour: BrowserGettingStartedTour?

        init(
            state: BrowserGettingStartedState = BrowserGettingStartedState(),
            guideContext: @escaping () -> BrowserGettingStartedGuideContext? = { nil },
            openSearchSettings: @escaping () -> Bool = { false }, browse: @escaping () -> Void = {},
            openURL: @escaping (URL) -> Void
        ) {
            self.state = state
            self.browse = browse
            self.guideContext = guideContext
            self.openSearchSettings = openSearchSettings
            self.openURL = openURL
        }

        var body: some View {
            GeometryReader { geometry in
                if let tour, tour.isShowingGuide {
                    VStack(spacing: OdeSpacing.large) {
                        masthead
                        BrowserGettingStartedTourView(tour: tour, runCommand: actions.runCommand) {
                            tour.dismiss(completed: true)
                            state.chapter = .moves
                        }
                    }
                    .padding(geometry.size.width < 600 ? OdeSpacing.large : 30)
                    .background(OdeBrandTheme.canvas)
                } else {
                    ScrollView {
                        VStack(spacing: OdeSpacing.extraExtraLarge) {
                            masthead
                            if state.chapter.showsMoves, let moves {
                                BrowserGettingStartedMovesStage(
                                    moves: moves, selection: $state.move, runCommand: actions.runCommand,
                                    context: guideContext(), openSearchSettings: openSearchSettings,
                                    practiceSplit: { selectChapter(.splitView) },
                                    compact: geometry.size.height < 500
                                )
                                .frame(minHeight: max(260, geometry.size.height - 140))
                            } else {
                                practiceStage(wide: geometry.size.width >= 820, height: geometry.size.height)
                            }
                        }
                        .padding(geometry.size.width < 600 ? OdeSpacing.large : 30)
                        .frame(maxWidth: 1080).frame(maxWidth: .infinity)
                    }
                    .browserNativeScrollState(state.scroll)
                    .background(OdeBrandTheme.canvas)
                }
            }
            .environment(practice.sidebarInteraction)
            .onDisappear { practice.sidebarInteraction.cancel() }
            .onChange(of: moves?.requestedMove, initial: true) { _, requested in
                guard let requested else { return }
                tour?.dismiss()
                state.chapter = .moves
                state.move = requested
                moves?.requestedMove = nil
            }
            .font(OdeTypography.sans(14))
        }

        private var masthead: some View {
            HStack(spacing: OdeSpacing.small) {
                OdeMark().frame(width: 22, height: 22)
                Text("Getting Started").font(OdeTypography.sans(13, weight: .semibold))
                Spacer()
                if tour?.isRunning != true {
                    topics
                    Button("Browse", systemImage: "arrow.right", action: browse).buttonStyle(.odeSecondary)
                }
            }
        }

        private var topics: some View {
            Menu {
                Group {
                    if let tour {
                        Button("Take the quick tour", systemImage: "play") { tour.replay() }
                    }
                    Menu("Everyday moves", systemImage: "command") {
                        ForEach(BrowserGettingStartedMove.allCases) { move in
                            Button {
                                state.chapter = .moves
                                state.move = move
                            } label: {
                                Label(
                                    move.cue,
                                    systemImage: moves?.done.contains(move) == true ? "checkmark.circle" : "circle")
                            }
                        }
                        .odeMenuActionLabelStyle()
                    }
                    Menu("Tabs & folders", systemImage: "folder") {
                        ForEach(BrowserGettingStartedLesson.all) { lesson in
                            Button(lesson.title, systemImage: "rectangle.on.rectangle") {
                                state.chapter = .tabs
                                state.lesson = lesson
                            }
                        }
                        .odeMenuActionLabelStyle()
                    }
                    Button("Split View", systemImage: "rectangle.split.2x1") { selectChapter(.splitView) }
                    Divider()
                    Button(
                        state.chapter.showsMoves ? "Reset progress" : "Reset practice",
                        systemImage: "arrow.counterclockwise"
                    ) {
                        practice.reset()
                        state.lesson = .pin
                        if state.chapter.showsMoves {
                            moves?.reset()
                            state.move = .commandBar
                        }
                    }
                }
                .odeMenuActionLabelStyle()
            } label: {
                Label("Explore", systemImage: "book")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .odeControlPointer()
            .accessibilityLabel("Explore Getting Started")
        }

        private func practiceStage(wide: Bool, height: CGFloat) -> some View {
            VStack(spacing: OdeSpacing.large) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OdeSpacing.extraExtraLarge) {
                        practiceCue.frame(width: 260)
                        practiceWindow(height: height).frame(width: wide ? 580 : 480)
                    }
                    VStack(spacing: OdeSpacing.large) {
                        practiceCue
                        practiceWindow(height: height)
                    }
                }
                HStack(spacing: OdeSpacing.large) {
                    Spacer(minLength: 0)
                    if state.chapter.showsLessons {
                        Text("\(state.lesson.number) of \(BrowserGettingStartedLesson.all.count)")
                            .font(OdeTypography.sans(13)).foregroundStyle(OdeBrandTheme.textSecondary)
                        Button(lessonIsDone ? "Next" : "Skip", systemImage: "arrow.right") { nextLesson() }
                            .buttonStyle(.odeSecondary)
                    }
                }
            }
        }

        private func practiceWindow(height: CGFloat) -> some View {
            BrowserGettingStartedPracticeWindow(practice: practice, showsSplit: state.chapter.showsSplit)
                .frame(height: min(400, max(280, height * 0.58)))
        }

        private var practiceCue: some View {
            VStack(spacing: OdeSpacing.medium) {
                if state.chapter.showsSplit {
                    splitCue
                } else {
                    Text(lessonIsDone ? "Done" : lessonCue).font(OdeTypography.display(30))
                    if !lessonIsDone {
                        Text("Only this example Space changes.")
                            .font(OdeTypography.sans(12)).foregroundStyle(OdeBrandTheme.textSecondary)
                        lessonAction
                    }
                }
                Image(decorative: "OdeWelcomeBeret").resizable().scaledToFit().frame(height: 64)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
        }

        private var lessonCue: LocalizedStringKey {
            switch state.lesson.kind {
            case .pin: "Keep an app close"
            case .save: "Keep a tab for later"
            case .folders: "Give ideas a home"
            case .clear: "Clear some space"
            }
        }

        private var lessonIsDone: Bool {
            switch state.lesson.kind {
            case .pin:
                practice.tabID(.mail).flatMap { practice.space.tabs.model($0) }?.placement == .pinned
            case .save:
                practice.tabID(.trail).flatMap { practice.space.tabs.model($0) }?.placement == .saved
            case .folders:
                practice.space.folders.models.contains { $0.parentID != nil }
            case .clear:
                !practice.space.tabs.models.contains { $0.placement == .current }
            }
        }

        @ViewBuilder private var lessonAction: some View {
            switch state.lesson.kind {
            case .pin:
                Text("Pins stay at the top.").foregroundStyle(OdeBrandTheme.textSecondary)
                BrowserGettingStartedPinAction(practice: practice, style: .odePrimary)
            case .save:
                Text("Saved tabs stay until you remove them.").foregroundStyle(OdeBrandTheme.textSecondary)
                BrowserGettingStartedSaveAction(
                    practice: practice, title: "Save A weekend away", systemImage: "bookmark", style: .odePrimary)
            case .folders:
                let hasFolder = practice.space.folders.models.contains { $0.title == "Weekends" }
                Button(hasFolder ? "Nest Ideas" : "Add Weekends", systemImage: "folder.badge.plus") {
                    practice.addFolder(nested: hasFolder)
                }
                .buttonStyle(.odePrimary)
            case .clear:
                Text("Current tabs go to Archive. Pins and saved tabs stay.")
                    .font(OdeTypography.sans(14)).foregroundStyle(OdeBrandTheme.textSecondary)
                BrowserGettingStartedCleanUpAction(practice: practice)
            }
        }

        @ViewBuilder private var splitCue: some View {
            if practice.members.count < 2 {
                Text("Put two pages together").font(OdeTypography.display(30))
                Text("Only this example Space changes.")
                    .font(OdeTypography.sans(12)).foregroundStyle(OdeBrandTheme.textSecondary)
                Button("Add Packing list", systemImage: "plus.rectangle.on.rectangle") { practice.makeSplit() }
                    .buttonStyle(.odePrimary)
            } else {
                Text("Move a page").font(OdeTypography.display(30))
                Text("Only this example Space changes.")
                    .font(OdeTypography.sans(12)).foregroundStyle(OdeBrandTheme.textSecondary)
                Text("Click a page to choose it.").foregroundStyle(OdeBrandTheme.textSecondary)
                if let selected = practice.selectedTabID {
                    HStack(spacing: OdeSpacing.small) {
                        Button("Move left", systemImage: "arrow.left") { practice.move(selected, by: -1) }
                            .disabled(
                                !practice.browser.canMoveSplitMember(selected, by: -1, matching: practice.assignment))
                        Button("Move right", systemImage: "arrow.right") { practice.move(selected, by: 1) }
                            .disabled(
                                !practice.browser.canMoveSplitMember(selected, by: 1, matching: practice.assignment))
                    }
                    .buttonStyle(.odeSecondary)
                }
            }
        }

        private func nextLesson() {
            if let next = state.lesson.next { state.lesson = next } else { selectChapter(.splitView) }
        }

        private func selectChapter(_ next: BrowserGettingStartedChapter) {
            if next.showsSplit && state.chapter != next { practice.reset() }
            state.chapter = next
        }
    }
#endif
