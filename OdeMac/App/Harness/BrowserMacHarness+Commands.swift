#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import SwiftUI
    import WebKit

    /// The harness's commands, each acting through the path the menus, keys
    /// and windows use. An app that never activates has no key window, so
    /// commands act in the browser window the person used last.
    extension BrowserMacHarness {
        /// One command: its arguments in, its reply's fields out.
        typealias Command = @MainActor ([String: Any]) async throws -> [String: Any]

        struct Failure: Error, CustomStringConvertible, Sendable {
            let description: String
        }

        /// Answers one command line with one reply line.
        func reply(to request: Data) async -> Data {
            let (command, arguments) = Self.decode(request)
            do {
                return Self.encode(.success(try await perform(command, arguments)), command: command)
            } catch {
                return Self.encode(.failure(error), command: command)
            }
        }

        /// A request line's command and its arguments; no command when the
        /// line is not a JSON object.
        nonisolated static func decode(_ request: Data) -> (command: String, arguments: [String: Any]) {
            let object = (try? JSONSerialization.jsonObject(with: request)) as? [String: Any] ?? [:]
            return (object["command"] as? String ?? "", object)
        }

        /// The reply line for `command`: its result with `ok`, or the error.
        nonisolated static func encode(_ outcome: Result<[String: Any], any Error>, command: String) -> Data {
            var reply: [String: Any]
            switch outcome {
            case .success(let result):
                reply = result
                reply["ok"] = true
            case .failure(let error):
                reply = ["ok": false, "error": String(describing: error)]
            }
            reply["command"] = command
            return (try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]))
                ?? Data(#"{"ok":false}"#.utf8)
        }

        private func perform(_ command: String, _ arguments: [String: Any]) async throws -> [String: Any] {
            guard let run = commandTable[command] else {
                throw Failure(description: "Unknown command \(command)")
            }
            return try await run(arguments)
        }

        /// Every command the harness answers, by name.
        private var commandTable: [String: Command] {
            [
                sessionCommands,
                navigationCommands,
                recoveryCommands,
                commandBarCommands,
                surfaceCommands,
                siteCommands,
                tabPreviewAndDownloadCommands,
                pageCommands,
                libraryCommands,
                sidebarCommands,
                diagnosticCommands,
            ].reduce(into: [:]) { table, group in table.merge(group) { first, _ in first } }
        }

        // MARK: - Command tables

        /// Commands about the session as a whole: its state, quitting, demo data, appearance and preferences.
        private var sessionCommands: [String: Command] {
            [
                "ping": { [self] _ in
                    return ["pid": Int(getpid()), "phases": phases.map(\.rawValue)]
                },
                "state": { [self] _ in
                    return state()
                },
                "quit": { [self] arguments in
                    quitSoon(clean: arguments["clean"] as? Bool ?? true)
                    return [:]
                },
                "setupDemo": { [self] arguments in
                    return try await setupDemo(arguments["spaces"] as? [[String: Any]] ?? [])
                },
                "allowAgent": { [self] arguments in
                    return try allowAgent(arguments)
                },
                "setAppearance": { arguments in
                    // Ode's own choice, as Appearance settings make it, which the
                    // session keeps for its next launch.
                    BrowserDeviceAppearanceStore.shared.mode =
                        BrowserAppearanceMode.named(arguments["mode"] as? String) ?? .system
                    return [:]
                },
                "targetPrivateWindow": { arguments in
                    Self.targetsPrivateWindow = arguments["on"] as? Bool ?? true
                    return ["private": Self.targetsPrivateWindow]
                },
                "setPaletteSource": { [self] arguments in
                    return try setPaletteSource(arguments)
                },
                "setSearchSuggestions": { [self] arguments in
                    _ = try context().browser.core.send(SetSearchSuggestions(enabled: arguments["on"] as? Bool ?? true))
                    return [:]
                },
                "performCommand": { [self] arguments in
                    let name = arguments["name"] as? String
                    guard let command = ShortcutCommand.named(name) else {
                        throw Failure(description: "No command is named \(name ?? "")")
                    }
                    let actions = try commands()
                    guard actions.canPerform(command) else {
                        throw Failure(description: "\(command.name) is not available")
                    }
                    actions.perform(command)
                    return [:]
                },
                "splitWithNextTab": { [self] _ in
                    try commands().splitWithNextTab()
                    return [:]
                },
            ]
        }

        /// Commands that open, select and move between tabs, Spaces and pages, and type into them.
        private var navigationCommands: [String: Command] {
            [
                "openNewTab": { [self] _ in
                    try commands().openNewTab()
                    return [:]
                },
                "loadURL": { [self] arguments in
                    guard let address = arguments["url"] as? String, let url = URL(string: address),
                        let tabID = try context().browser.openNewTab(url: url)
                    else { throw Failure(description: "The address could not be opened") }
                    return ["tabID": tabID.uuidString]
                },
                "selectTab": { [self] arguments in
                    guard let id = (arguments["id"] as? String).flatMap(UUID.init(uuidString:)) else {
                        throw Failure(description: "selectTab needs a tab id")
                    }
                    try context().browser.selectTab(id)
                    return [:]
                },
                "selectSpace": { [self] arguments in
                    let name = arguments["name"] as? String
                    let browser = try context().browser
                    guard let space = browser.spaceModels.first(where: { $0.settings.name == name }) else {
                        throw Failure(description: "No Space is named \(name ?? "")")
                    }
                    browser.selectSpace(space.id)
                    return ["spaceID": space.id.uuidString]
                },
                "selectTabMatching": { [self] arguments in
                    let text = arguments["text"] as? String ?? ""
                    let browser = try context().browser
                    guard
                        let tab = browser.shownSpace?.tabs.models.first(where: {
                            ($0.url ?? "").contains(text) || $0.title.contains(text)
                        })
                    else { throw Failure(description: "No tab in the shown Space matches \(text)") }
                    browser.selectTab(tab.id)
                    return ["tabID": tab.id.uuidString]
                },
                "typeText": { [self] arguments in
                    guard let editor = try targetWindow().firstResponder as? NSTextView else {
                        throw Failure(description: "Nothing that takes text has the keyboard")
                    }
                    editor.insertText(
                        arguments["text"] as? String ?? "", replacementRange: NSRange(location: NSNotFound, length: 0))
                    return [:]
                },
                "pressKey": { [self] arguments in
                    try press(arguments["key"] as? String ?? "")
                    return [:]
                },
                "measureSpaceSwitch": { [self] arguments in
                    return try await measureSpaceSwitch(
                        name: arguments["name"] as? String ?? "", seconds: arguments["seconds"] as? Double ?? 0.8)
                },
                "openFromTab": { [self] arguments in
                    return try openFromTab(
                        arguments["url"] as? String ?? "", matching: arguments["from"] as? String ?? "",
                        shows: arguments["shows"] as? Bool ?? false)
                },
                "openPeek": { [self] arguments in
                    // Opens `url` in Peek over the shown page, as its context menu does.
                    guard let address = arguments["url"] as? String, let url = URL(string: address),
                        let page = try context().pages.activePage, let source = page.navigationContext
                    else { throw Failure(description: "openPeek needs a url and a shown page") }
                    page.openPeek(
                        BrowserPeekRequest(
                            url: url, sourceTabID: source.tabID, sourceTitle: source.title,
                            spaceAssignment: source.spaceAssignment, trigger: .contextMenu))
                    return ["opened": true]
                },
                "sleepTab": { [self] arguments in
                    return try sleepTab(matching: arguments["text"] as? String ?? "")
                },
            ]
        }

        /// Commands about kept copies, frozen pages, crash reports and updates.
        private var recoveryCommands: [String: Command] {
            [
                "listRecoveryCopies": { [self] _ in
                    return ["copies": BrowserRecoveryCopies.list(in: directory).map(describe)]
                },
                "restoreCopy": { [self] arguments in
                    guard let name = arguments["name"] as? String,
                        let copy = BrowserRecoveryCopies.list(in: directory).first(where: { $0.name == name })
                    else { throw Failure(description: "No kept copy has that name") }
                    guard BrowserRecoveryCopies.requestRestore(copy, in: directory) else {
                        throw Failure(description: "The restore request could not be saved")
                    }
                    if arguments["quit"] as? Bool ?? true { quitSoon(clean: true) }
                    return ["requested": name]
                },
                "showRestoreWindow": { [self] _ in
                    shell.restoreEarlierCopy()
                    return [:]
                },
                "keepCurrentSession": { [self] _ in
                    shell.application?.heldCopy?.keepThisSession()
                    return ["held": shell.application?.heldCopy?.copy != nil]
                },
                "freezeVisiblePage": { [self] _ in
                    return try await freezeVisiblePage()
                },
                "frozenBarState": { [self] _ in
                    let page = try context().pages.activePage
                    return ["frozen": page?.responsiveness.isFrozen ?? false, "hasPage": page != nil]
                },
                "stopFrozenPage": { [self] _ in
                    let context = try context()
                    guard let tabID = context.browser.shownTab?.id else {
                        throw Failure(description: "No tab is shown")
                    }
                    context.pages.stopUnresponsivePage(tabID)
                    return ["tabID": tabID.uuidString]
                },
                "reports": { [self] _ in
                    let reports = shell.application?.crashReports
                    return [
                        "reports": (reports?.reports ?? []).map(describe),
                        "unnoticed": reports?.unnoticed.count ?? 0,
                    ]
                },
                "dismissReportNotice": { [self] _ in
                    return try dismissReportNotice()
                },
                "showCrashNotice": { [self] _ in
                    return try showCrashNotice()
                },
                "showSoftwareUpdate": { [self] arguments in
                    return try showSoftwareUpdate(arguments)
                },
                "showEarlierVersions": { [self] arguments in
                    return showEarlierVersions(stage: arguments["stage"] as? String ?? "list")
                },
            ]
        }

        /// Commands that show, measure and close the command bar.
        private var commandBarCommands: [String: Command] {
            [
                "showCommandBar": { [self] _ in
                    return try showCommandBar()
                },
                "commandBar": { [self] _ in
                    return try commandBarState()
                },
                "closeCommandBar": { [self] _ in
                    try context().chrome.dismissCommandPalette()
                    return [:]
                },
                "commandBarState": { [self] _ in
                    return try commandBarState()
                },
                "measureCommandBar": { [self] arguments in
                    return try await measureCommandBar(
                        runs: arguments["runs"] as? Int ?? 30, settle: arguments["settleMs"] as? Int ?? 250)
                },
                "holdCommandBarBloom": { arguments in
                    // The bloom lasts under a second, less than a capture takes to
                    // start; held, every provider the bar enters shows that moment.
                    BrowserSearchProviderBloom.heldMoment = arguments["moment"] as? Double
                    return [:]
                },
            ]
        }

        /// Commands that present settings, setup, prompts and other surfaces, for capture or inspection.
        private var surfaceCommands: [String: Command] {
            [
                "openSettings": { [self] arguments in
                    // A pane by name, or a page of the shown Space by `spaceTab`,
                    // with `search` in the search field.
                    let name = arguments["pane"] as? String
                    let request: any BrowserSettingsRequest
                    if let tabName = arguments["spaceTab"] as? String {
                        guard let tab = BrowserSpaceSettingsTab.named(tabName) else {
                            throw Failure(description: "No Space page is named \(tabName)")
                        }
                        request = BrowserSettingsSpaceRequest(tab: tab)
                    } else {
                        guard let destination = BrowserSettingsDestination.all.first(where: { $0.name == name }) else {
                            throw Failure(description: "No settings pane is named \(name ?? "")")
                        }
                        request =
                            BrowserSpaceSettingsTab.holding(destination).map { BrowserSettingsSpaceRequest(tab: $0) }
                            ?? BrowserSettingsDestinationRequest(destination: destination)
                    }
                    guard let application = shell.application else {
                        throw Failure(description: "The browser is not running")
                    }
                    application.openSettings(
                        request, searchText: arguments["search"] as? String, in: try context().windowID)
                    return [:]
                },
                "openImportSetup": { [self] _ in
                    guard let windows = shell.windows else { throw Failure(description: "The browser is not running") }
                    windows.openOnboardingWindow(.importBrowser)
                    return ["window": BrowserOnboardingWindowActivation.windowTitle]
                },
                "showSiteSettings": { [self] arguments in
                    return try showSiteSettings(blockedOnly: arguments["blockedOnly"] as? Bool ?? false)
                },
                "closeSurface": { [self] _ in
                    surfaceWindow?.close()
                    surfaceWindow = nil
                    return [:]
                },
                "presentForCapture": { [self] arguments in
                    return try presentForCapture(
                        window: arguments["window"] as? String, on: arguments["on"] as? Bool ?? true,
                        width: arguments["width"] as? Double, height: arguments["height"] as? Double)
                },
                "showMarks": { [self] arguments in
                    let sides = (arguments["sides"] as? [Double] ?? [16, 32, 64, 256]).map { CGFloat($0) }
                    return show(
                        HarnessMarks(sides: sides), titled: "Marks", width: sides.reduce(64, +) + 48, capturable: true)
                },
                "showUtility": { [self] arguments in
                    return try showUtility(arguments["surface"] as? String)
                },
                "showNavigationFailure": { [self] arguments in
                    return try showNavigationFailure(arguments)
                },
                "showPermissionPrompt": { [self] arguments in
                    return try showPermissionPrompt(arguments)
                },
                "drawWindowsActive": { arguments in
                    let appearance = BrowserMacHarnessActiveAppearance.shared
                    appearance.drawsActive = arguments["on"] as? Bool ?? true
                    appearance.increasedContrast = arguments["increasedContrast"] as? Bool
                    appearance.reduceTransparency = arguments["reduceTransparency"] as? Bool
                    return ["active": appearance.drawsActive]
                },
                "showEverydayMoves": { [self] arguments in
                    return try showEverydayMoves(arguments)
                },
                "showGettingStartedMove": { [self] arguments in
                    return try showGettingStartedMove(arguments)
                },
                "showImportStage": { [self] arguments in
                    return try showImportStage(arguments)
                },
            ]
        }

        /// Commands about Boosts, site controls and Focus.
        private var siteCommands: [String: Command] {
            [
                "setBoost": { [self] arguments in
                    return try setBoost(arguments)
                },
                "removeBoost": { [self] arguments in
                    return try removeBoost(site: arguments["site"] as? String)
                },
                "editBoost": { [self] arguments in
                    return try editBoost(on: arguments["on"] as? Bool ?? true, hiding: arguments["hiding"] as? Bool)
                },
                "boostState": { [self] _ in
                    return try await boostState()
                },
                "clickPage": { [self] arguments in
                    return try clickPage(x: arguments["x"] as? Double ?? 0, y: arguments["y"] as? Double ?? 0)
                },
                "showSiteControls": { [self] _ in
                    return try showSiteControls()
                },
                "showBoostPanel": { [self] arguments in
                    return try showBoostPanel(arguments["panel"] as? String ?? "colors")
                },
                "focus": { [self] arguments in
                    return try focus(arguments)
                },
                "showFocusPause": { [self] arguments in
                    return showFocusPause(
                        site: arguments["site"] as? String ?? "", minutes: arguments["minutes"] as? Int ?? 30)
                },
            ]
        }

        /// Commands about tab previews and downloads.
        private var tabPreviewAndDownloadCommands: [String: Command] {
            [
                "standInTabPreviewSite": { [self] arguments in
                    return try standInTabPreviewSite(
                        origin: arguments["origin"] as? String ?? "", site: arguments["site"] as? String)
                },
                "tabPreviews": { [self] arguments in
                    return try await tabPreviews(
                        count: arguments["count"] as? Int ?? 0, timeout: arguments["timeout"] as? Double ?? 10)
                },
                "showTabPreview": { [self] arguments in
                    return try showTabPreview(matching: arguments["text"] as? String ?? "")
                },
                "hideTabPreview": { [self] _ in
                    return try hideTabPreview()
                },
                "openTabPreviewItem": { [self] arguments in
                    return try await openTabPreviewItem(
                        matching: arguments["text"] as? String ?? "", index: arguments["index"] as? Int ?? 0)
                },
                "setDownloadFolder": { [self] arguments in
                    return try setDownloadFolder(arguments["path"] as? String ?? "")
                },
                "startDownload": { [self] arguments in
                    return try startDownload(
                        arguments["url"] as? String ?? "", x: arguments["x"] as? Double, y: arguments["y"] as? Double)
                },
                "downloads": { [self] arguments in
                    return try await downloads(
                        count: arguments["count"] as? Int ?? 0, phase: arguments["phase"] as? String,
                        timeout: arguments["timeout"] as? Double ?? 10)
                },
                "cancelDownloads": { [self] _ in
                    return try cancelDownloads()
                },
                "recentDownloads": { [self] _ in
                    return try recentDownloads()
                },
                "hideRecentDownloads": { [self] _ in
                    return try hideRecentDownloads()
                },
                "clearDownloads": { [self] _ in
                    return try clearDownloads()
                },
                "showDownloads": { [self] arguments in
                    return try showDownloads(arguments["on"] as? Bool ?? true)
                },
            ]
        }

        /// Commands that probe and drive pages, Quick Windows, extensions and shortcuts.
        private var pageCommands: [String: Command] {
            [
                "probePage": { [self] arguments in
                    return try await probePage(
                        arguments["script"] as? String ?? "", timeout: arguments["timeout"] as? Double ?? 5)
                },
                "capturePage": { [self] arguments in
                    return try await capturePage(named: arguments["name"] as? String ?? "")
                },
                "browserSheet": { [self] arguments in
                    return try browserSheet(press: arguments["press"] as? Int)
                },
                "inputPage": { [self] arguments in
                    return try await inputPage(arguments)
                },
                "credentialState": { [self] _ in
                    return try credentialState()
                },
                "fullscreen": { [self] _ in
                    return try fullscreenState()
                },
                "openQuickWindow": { [self] arguments in
                    return try openQuickWindow(arguments["url"] as? String ?? "")
                },
                "showQuickWindowPicker": { [self] _ in
                    return try showQuickWindowPicker()
                },
                "quickWindowOpen": { [self] arguments in
                    return try quickWindowOpen(arguments)
                },
                "quickWindowState": { [self] _ in
                    return try quickWindowState()
                },
                "installExtensions": { [self] arguments in
                    return try installExtensions(arguments["items"] as? [[String: Any]] ?? [])
                },
                "extensions": { [self] _ in
                    return try await installedExtensions()
                },
                "offerShortcut": { [self] arguments in
                    return try offerUnclaimedShortcut(arguments["key"] as? String ?? "")
                },
            ]
        }

        /// Commands about imported Spaces and history, site icons and media sessions.
        private var libraryCommands: [String: Command] {
            [
                "importUnloadedSpace": { [self] arguments in
                    return try importUnloadedSpace(arguments)
                },
                "importHistory": { [self] arguments in
                    return try importHistory(arguments)
                },
                "historyList": { [self] arguments in
                    return try await historyList(arguments)
                },
                "siteIcons": { [self] arguments in
                    return try await siteIcons(arguments)
                },
                "stageMediaSession": { [self] arguments in
                    return try stageMediaSession(arguments)
                },
                "mediaSessions": { [self] _ in
                    return try mediaSessions()
                },
                "mediaReturnRoute": { [self] _ in
                    return try mediaReturnRoute()
                },
                "backToPlayingTab": { [self] _ in
                    return try await backToPlayingTab()
                },
            ]
        }

        /// Commands that show, peek, lay out and read the sidebar and its tab tree.
        private var sidebarCommands: [String: Command] {
            [
                "toggleSidebar": { [self] arguments in
                    return try await toggleSidebar(settle: arguments["settle"] as? Double ?? 0.8)
                },
                "peekSidebar": { [self] arguments in
                    return try await peekSidebar(
                        arguments["on"] as? Bool ?? true, settle: arguments["settle"] as? Double ?? 0.8)
                },
                "sidebarState": { [self] _ in
                    return try sidebarState()
                },
                "peekTopBar": { [self] arguments in
                    return try await peekTopBar(
                        arguments["on"] as? Bool ?? true, settle: arguments["settle"] as? Double ?? 0.8)
                },
                "showIconTitle": { [self] arguments in
                    return try showIconTitle(matching: arguments["text"] as? String ?? "")
                },
                "setLayout": { [self] arguments in
                    return try await setLayout(
                        tabs: arguments["tabs"] as? String, density: arguments["density"] as? String,
                        sidebar: arguments["sidebar"] as? String, settle: arguments["settle"] as? Double ?? 0.8)
                },
                "scrollSidebar": { [self] arguments in
                    return try scrollSidebar(to: arguments["y"] as? Double ?? 0)
                },
                "sidebarOffset": { [self] _ in
                    return try sidebarOffset()
                },
                "setNesting": { [self] arguments in
                    return setNesting(arguments["on"] as? Bool ?? true)
                },
                "collapseNested": { [self] arguments in
                    return try collapseNested(
                        matching: arguments["text"] as? String ?? "", collapsed: arguments["collapsed"] as? Bool ?? true
                    )
                },
                "tabTree": { [self] _ in
                    return try tabTree()
                },
            ]
        }

        /// Commands that read frames, layers, accessibility and WebKit features, and take snapshots.
        private var diagnosticCommands: [String: Command] {
            [
                "floatingSurfaces": { [self] arguments in
                    return try floatingSurfaces(window: arguments["window"] as? String)
                },
                "nativeAccessibility": { [self] arguments in
                    return try nativeAccessibility(window: arguments["window"] as? String)
                },
                "scrollNativeContent": { [self] arguments in
                    return try scrollNativeContent(
                        to: arguments["y"] as? Double ?? 0, window: arguments["window"] as? String)
                },
                "moments": { [self] arguments in
                    return try moments(reset: arguments["reset"] as? Bool ?? false)
                },
                "sampleFrames": { [self] arguments in
                    return try await sampleFrames(arguments)
                },
                "pageLayers": { [self] arguments in
                    return try pageLayers(depth: arguments["depth"] as? Int ?? 6)
                },
                "webKitFeatures": { arguments in
                    let text = arguments["matching"] as? String ?? ""
                    let store = BrowserWebKitFeatureFlagStore.active
                    return [
                        "features": store.features.filter { $0.key.localizedCaseInsensitiveContains(text) }.map {
                            flag in
                            ["key": flag.key, "override": store.override(for: flag)?.rawValue ?? ""]
                        }
                    ]
                },
                "keepPagesDrawing": { [self] _ in
                    keepPagesDrawing(in: try targetWindow())
                    return [:]
                },
                "snapshotWindow": { [self] arguments in
                    // A sandboxed build writes only inside its container: the
                    // snapshot goes beside the session, and the client copies it out.
                    guard let name = arguments["name"] as? String, !name.contains("/") else {
                        throw Failure(description: "snapshotWindow needs a file name")
                    }
                    let folder = directory.appendingPathComponent("Snapshots", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    return try await snapshot(
                        window: arguments["window"] as? String, to: folder.appendingPathComponent(name + ".png"))
                },
            ]
        }

        // MARK: - Actions - Windows

        /// Whether keys, text and commands go to the private window, as
        /// `targetPrivateWindow` asks.
        static var targetsPrivateWindow = false

        func context() throws -> BrowserMacWindowContext {
            if Self.targetsPrivateWindow {
                guard let context = shell.windows?.privateWindowContext else {
                    throw Failure(description: "No private window is open")
                }
                return context
            }
            guard let context = shell.windows?.lastUsedContext else {
                throw Failure(description: "No browser window is open")
            }
            return context
        }

        func commands() throws -> BrowserCommandActions {
            guard let windows = shell.windows else { throw Failure(description: "The browser is not running") }
            return windows.actions(in: try context())
        }

        /// The window a key or text goes to: the browser window the person
        /// used last, else the frontmost of the harness's windows.
        func targetWindow() throws -> NSWindow {
            if let context = try? context(), let window = shell.windows?.window(for: context.windowID) { return window }
            if let window = NSApp.orderedWindows.first(where: \.isVisible) { return window }
            throw Failure(description: "No window is open")
        }

        func window(named name: String?) throws -> NSWindow {
            switch name {
            case nil, "browser": return try targetWindow()
            case let title?:
                guard let window = NSApp.orderedWindows.first(where: { $0.isVisible && $0.title == title }) else {
                    throw Failure(description: "No window is titled \(title)")
                }
                return window
            }
        }

        private func state() -> [String: Any] {
            let displayTop = NSScreen.screens.first?.frame.maxY ?? 0
            var state: [String: Any] = [
                "phases": phases.map(\.rawValue),
                "accessibilityDisplays": NSScreen.screens.map { screen in
                    [
                        "x": screen.frame.minX, "y": displayTop - screen.frame.maxY,
                        "width": screen.frame.width, "height": screen.frame.height,
                    ]
                },
                "active": NSApp.isActive,
                "activationPolicy": NSApp.activationPolicy() == .accessory ? "accessory" : "other",
                "askingHowToStart": shell.isAskingHowToStart,
                "showingRecovery": shell.isShowingRecovery,
                "windows": NSApp.windows.filter(\.isVisible).map { window -> [String: Any] in
                    [
                        "title": window.title, "key": window.isKeyWindow, "onScreen": window.screen != nil,
                        "intersectsPhysicalDisplay": NSScreen.screens.contains { $0.frame.intersects(window.frame) },
                        "class": String(describing: type(of: window)),
                        "x": window.frame.minX, "y": window.frame.minY,
                        "width": window.frame.width, "height": window.frame.height,
                        "alpha": window.alphaValue,
                        "ignoresMouseEvents": window.ignoresMouseEvents,
                        "collectionBehavior": window.collectionBehavior.rawValue,
                    ]
                },
            ]
            if let application = shell.application {
                state["safeMode"] = application.safeMode != nil
                state["missingTabsBanner"] = application.heldCopy?.message != nil
                state["reportNotice"] = !(application.crashReports?.unnoticed.isEmpty ?? true)
            }
            if let context = try? context() {
                let tab = context.browser.shownTab
                state["space"] = context.browser.shownSpace?.settings.name
                state["tab"] = [
                    "id": tab?.id.uuidString ?? "", "title": tab?.title ?? "", "url": tab?.url ?? "",
                    "startPage": tab?.surface == .startPage,
                ]
                state["commandBarOpen"] = context.chrome.isCommandPalettePresented
                state["commandBarFocused"] = (try? isCommandBarFieldFocused(in: targetWindow())) ?? false
                state["pageFrozen"] = context.pages.activePage?.responsiveness.isFrozen ?? false
                if let page = context.pages.activePage {
                    state["contentBlocking"] = [
                        "active": page.isContentBlockingActive,
                        "ruleLists": page.webKitAdapter?.contentRuleSession.ruleLists.count ?? 0,
                        "allowedForSite": SiteContentBlockingSwitch(
                            core: context.browser.core, spaceID: page.spaceID, url: page.live.displayURL)?.blocks
                            == false,
                        "blocked": page.blockedLoads.total,
                        "blockedSites": page.blockedLoads.sites.map { ["site": $0.site, "count": $0.count] },
                    ]
                }
            }
            return state
        }

        private func isCommandBarFieldFocused(in window: NSWindow) -> Bool {
            ((window.firstResponder as? NSTextView)?.delegate as? BrowserPlatformCommandPaletteField.Field) != nil
        }

        /// Quits once the reply is sent. A clean quit goes through
        /// `terminate:` from the run loop, as a menu's would: from inside a
        /// main-actor task it would wait on work that task holds back.
        private func quitSoon(clean: Bool) {
            if clean {
                NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0.05)
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    kill(getpid(), SIGKILL)
                }
            }
        }

        // MARK: - Actions - Surfaces

        /// Shows the shown page's Site Settings, as its site menu does, in a
        /// window titled "Site Settings" that `snapshotWindow` can draw;
        /// `blockedOnly` shows just what was blocked, opened out.
        private func showSiteSettings(blockedOnly: Bool) throws -> [String: Any] {
            guard let page = try context().pages.activePage else { throw Failure(description: "No page is shown") }
            if blockedOnly {
                return show(BrowserSiteBlockedLoadsSection(page: page, isExpanded: true), titled: "Site Settings")
            }
            return show(
                BrowserSiteSettingsContent(
                    page: page, permissionCenter: page.permissionCenter, permissionsExpansion: .constant(false)),
                titled: "Site Settings")
        }

        /// Shows the open Command Bar again, with its model as it is now, in a
        /// window the system can capture by its number. Drawing a window's
        /// layers leaves out Liquid Glass and everything grouped with it, such
        /// as the field's row while a provider chip shows, so this window sits
        /// beneath every other window with one point on a display, where the
        /// window server draws it whole and nobody sees it.
        private func showCommandBar() throws -> [String: Any] {
            show(HarnessCommandBar(model: try commandBarModel()), titled: "Command Bar", width: 720, capturable: true)
        }

        /// What the open Command Bar shows: its text and where the insertion
        /// point is in it, the provider or scope it is narrowed to, each row
        /// with its kind and any answer, the first rows' titles, the selected
        /// row and the answer button Return runs.
        private func commandBarState() throws -> [String: Any] {
            let model = try commandBarModel()
            var state: [String: Any] = [
                "query": model.query,
                "caret": (try targetWindow().firstResponder as? NSTextView)?.selectedRange().location ?? 0,
                "titles": model.items.prefix(8).map(\.row.title),
                "provider": model.activeProvider?.name ?? "",
                "scope": model.activeScope?.name ?? "",
                "scopeOffer": model.scopeOffer?.name ?? "",
                "selected": model.selectedResultIndex,
                "rows": model.items.map { item -> [String: Any] in
                    [
                        "kind": item.row.kind.name, "title": item.row.title, "address": item.row.address ?? "",
                        "answer": item.row.answer?.id ?? "", "topResult": item.row.topResult ?? "",
                        "card": item.row.card?.kind.name ?? "", "cardBody": item.row.card?.body ?? "",
                        "cardImage": item.row.card?.image?.credit ?? "",
                    ]
                },
            ]
            if model.items.indices.contains(model.selectedResultIndex) {
                let selected = model.items[model.selectedResultIndex]
                state["shiftReturn"] = model.shiftReturnOpening(for: selected.row)?.name ?? ""
                if model.selectedAnswer != nil { state["answerControl"] = model.answerControl(for: selected).name }
            }
            return state
        }

        /// Opens `text` in the newest Quick Window as its address field's
        /// Return does, or its Shift-Return with `shift`, and answers the
        /// address it opened.
        private func quickWindowOpen(_ arguments: [String: Any]) throws -> [String: Any] {
            let model = try quickWindowModel()
            let text = arguments["text"] as? String ?? ""
            let shifted = arguments["shift"] as? Bool == true
            guard let url = model.open(typed: text, topResult: shifted, isActive: true) else {
                throw Failure(description: "The Quick Window opened nothing")
            }
            return ["opened": url.absoluteString]
        }

        /// Turns the palette source `name` on or off, as Settings > Search
        /// does, and answers whether it is on.
        private func setPaletteSource(_ arguments: [String: Any]) throws -> [String: Any] {
            guard let source = PaletteSource.all.first(where: { $0.name == arguments["name"] as? String }) else {
                throw Failure(description: "setPaletteSource needs the name of a palette source")
            }
            let store = BrowserAppPreferenceStore.shared
            store.palette = store.palette.offering(source, arguments["enabled"] as? Bool ?? true)
            return ["enabled": store.palette.offers(source)]
        }

        /// What the newest Quick Window's page shows.
        private func quickWindowState() throws -> [String: Any] {
            let model = try quickWindowModel()
            return [
                "url": model.page?.live.url ?? "", "title": model.page?.live.title ?? "",
                "loading": model.page?.live.isLoading == true,
            ]
        }

        private func quickWindowModel() throws -> BrowserQuickWindowModel {
            guard let model = shell.windows?.quickWindowModels.last else {
                throw Failure(description: "No Quick Window is open")
            }
            return model
        }

        private func commandBarModel() throws -> BrowserCommandPaletteModel {
            guard let editor = try targetWindow().firstResponder as? NSTextView,
                let field = editor.delegate as? BrowserPlatformCommandPaletteField.Field,
                let coordinator = field.delegate as? BrowserPlatformCommandPaletteField.Coordinator
            else { throw Failure(description: "The Command Bar is not open") }
            return coordinator.model
        }

        /// Shows `content` in a window titled `title`, `width` wide and as
        /// tall as it needs, or `height` tall, with `padding` around it.
        func show(
            _ content: some View, titled title: String, width: CGFloat = 320, height: CGFloat? = nil,
            padding: CGFloat = OdeSpacing.medium, capturable: Bool = false
        ) -> [String: Any] {
            let host = NSHostingView(
                rootView: content.padding(padding).frame(width: width, height: height, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true))
            surfaceWindow?.close()
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            window.contentView = host
            window.orderFront(nil)
            if capturable, let screen = NSScreen.screens.first {
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                window.ignoresMouseEvents = true
                window.alphaValue = 1
                window.setFrameOrigin(
                    NSPoint(
                        x: screen.frame.minX - window.frame.width + 1, y: screen.frame.minY - window.frame.height + 1))
            }
            surfaceWindow = window
            return [
                "width": host.fittingSize.width, "height": host.fittingSize.height, "windowNumber": window.windowNumber,
            ]
        }

        // MARK: - Actions - Keys

        /// Presses `key` in the target window: the shell's shortcuts first,
        /// as its key monitor offers them, then the window's responders.
        /// New Tab's key acts in the last-used window, as the menu bar acts in
        /// the key one.
        private func press(_ key: String) throws {
            if key == "cmd+t" {
                try commands().openNewTab()
                return
            }
            let specs: [String: (characters: String, code: UInt16, flags: NSEvent.ModifierFlags)] = [
                "return": ("\r", 36, []), "escape": ("\u{1b}", 53, []), "tab": ("\t", 48, []),
                "shift+tab": ("\u{19}", 48, [.shift]),
                "down": (String(UnicodeScalar(NSDownArrowFunctionKey)!), 125, [.numericPad, .function]),
                "up": (String(UnicodeScalar(NSUpArrowFunctionKey)!), 126, [.numericPad, .function]),
                "cmd+l": ("l", 37, [.command]), "cmd+w": ("w", 13, [.command]),
                "shift+return": ("\r", 36, [.shift]),
                "ctrl+n": ("\u{0e}", 45, [.control]), "ctrl+p": ("\u{10}", 35, [.control]),
            ]
            guard let spec = specs[key] else { throw Failure(description: "Unknown key \(key)") }
            // A Control key types a control character, and AppKit binds it by
            // the letter it leaves once Control is let go.
            let unmodified = key.hasPrefix("ctrl+") ? String(key.dropFirst("ctrl+".count)) : spec.characters
            let window = try targetWindow()
            // The Command Bar learns the held keys from its key monitor,
            // which events sent straight to a window pass by.
            let palette = try? commandBarModel()
            palette?.updateHeldModifiers(EventModifiers(spec.flags))
            defer { if let palette, (try? commandBarModel()) === palette { palette.updateHeldModifiers([]) } }
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard
                    let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: spec.flags,
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, characters: spec.characters, charactersIgnoringModifiers: unmodified,
                        isARepeat: false, keyCode: spec.code)
                else { continue }
                if type == .keyDown,
                    shell.handleShortcut(
                        event,
                        at: BrowserWebHostView.isPageContent(window.firstResponder) ? .beforePage : .beforeOdeView)
                {
                    continue
                }
                window.sendEvent(event)
            }
        }

        // MARK: - Actions - Measuring

        /// Opens and closes the Command Bar `runs` times through New Tab, timing
        /// each open from the command to its rows, its field entering the
        /// window, the field taking the keyboard, and the commit of the frame
        /// that first shows it.
        private func measureCommandBar(runs: Int, settle: Int) async throws -> [String: Any] {
            let context = try context()
            let commands = try commands()
            try await showPage(in: context)
            var samples: [[String: Double]] = []
            for _ in 0..<max(1, runs) {
                if context.chrome.isCommandPalettePresented {
                    context.chrome.dismissCommandPalette()
                    try? await Task.sleep(for: .milliseconds(settle))
                }
                marks.removeAll()
                let start = DispatchTime.now().uptimeNanoseconds
                commands.openNewTab()
                let deadline = start + 3_000_000_000
                while !(seen(.focused) && seen(.frameCommitted)), DispatchTime.now().uptimeNanoseconds < deadline {
                    try? await Task.sleep(for: .milliseconds(1))
                }
                var sample: [String: Double] = [:]
                for mark in [BrowserCommandBarTiming.Mark.modelReady, .fieldInWindow, .focused, .frameCommitted] {
                    if let at = marks.first(where: { $0.mark == mark })?.at, at >= start {
                        sample[mark.rawValue] = Double(at - start) / 1_000_000
                    }
                }
                samples.append(sample)
                context.chrome.dismissCommandPalette()
                try? await Task.sleep(for: .milliseconds(settle))
            }
            return ["runs": samples, "summary": Self.summary(of: samples)]
        }

        private func seen(_ mark: BrowserCommandBarTiming.Mark) -> Bool {
            marks.contains { $0.mark == mark }
        }

        /// Median, 95th percentile, first and fastest of each timing, in ms.
        nonisolated static func summary(of samples: [[String: Double]]) -> [String: [String: Double]] {
            var summary: [String: [String: Double]] = [:]
            let keys = Set(samples.flatMap(\.keys))
            for key in keys {
                let values = samples.compactMap { $0[key] }
                guard let first = values.first else { continue }
                let sorted = values.sorted()
                let p95Index = min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)
                summary[key] = [
                    "median": sorted[sorted.count / 2], "p95": sorted[max(0, p95Index)], "first": first,
                    "min": sorted[0], "count": Double(sorted.count),
                ]
            }
            return summary
        }

        /// Shows a page rather than a start page, so New Tab opens the bar.
        private func showPage(in context: BrowserMacWindowContext) async throws {
            guard context.browser.shownTab == nil || context.browser.shownTab?.surface == .startPage else { return }
            guard
                let url = URL(
                    string: "data:text/html;charset=utf-8,%3Ctitle%3EHarness%20page%3C%2Ftitle%3E%3Cp%3EA%20page."),
                context.browser.openNewTab(url: url) != nil
            else { throw Failure(description: "No page could be opened") }
            try? await Task.sleep(for: .milliseconds(800))
        }

        // MARK: - Actions - Frozen pages

        /// Opens a page that stops answering two seconds after it loads, then
        /// interacts with it as a click would.
        private func freezeVisiblePage() async throws -> [String: Any] {
            let context = try context()
            let html =
                "<!doctype html><title>Frozen page</title><p>Stops answering two seconds after it loads.</p>"
                + "<script>setTimeout(() => { while (true) {} }, 2000)</script>"
            let encoded = html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            guard let url = URL(string: "data:text/html;charset=utf-8," + encoded),
                let tabID = context.browser.openNewTab(url: url)
            else { throw Failure(description: "The frozen page could not be opened") }
            try? await Task.sleep(for: .milliseconds(3500))
            guard let page = context.pages.activePage else { throw Failure(description: "The frozen page has no page") }
            page.responsiveness.interacted()
            return ["tabID": tabID.uuidString]
        }

        // MARK: - Actions - Snapshots

        /// Draws `name`'s window from its own views into a PNG at `url`, with
        /// each web view's own snapshot in place.
        private func snapshot(window name: String?, to url: URL) async throws -> [String: Any] {
            let window = try window(named: name)
            // A window off the screens draws only what was asked for; draw
            // every view now so each layer holds its current contents.
            // The frame view holds the title bar and every content view,
            // including hosting views placed beside the content view.
            let frameView = window.contentView?.superview ?? window.contentView
            frameView?.layoutSubtreeIfNeeded()
            frameView?.display()
            CATransaction.flush()
            guard let view = frameView, let layer = view.layer,
                let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds),
                let graphics = NSGraphicsContext(bitmapImageRep: representation)
            else { throw Failure(description: "The window has no content to draw") }
            // The layers hold what each view last drew, lists included, which
            // drawing the views again would leave out.
            // The context already maps points to the representation's pixels.
            let context = graphics.cgContext
            if layer.isGeometryFlipped {
                context.translateBy(x: 0, y: view.bounds.height)
                context.scaleBy(x: 1, y: -1)
            }
            // Rendering a layer tree draws sublayers in their order and
            // ignores `zPosition`, which a Space backdrop stacks its grounds
            // by; draw only the ground in front, as the screen shows it.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let covered = Self.hideCoveredGrounds(in: view)
            CATransaction.commit()
            layer.render(in: context)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (ground, opacity) in covered { ground.opacity = opacity }
            CATransaction.commit()
            // Each page's snapshot is drawn inside its host's clip, as the
            // window shows it: a floating card's page keeps the card's corner.
            var webSnapshots: [(image: NSImage, frame: NSRect, clip: NSRect, radius: CGFloat, roundsTop: Bool)] = []
            for webView in Self.webViews(in: view) where !webView.isHiddenOrHasHiddenAncestor {
                if let image = await Self.snapshot(of: webView) {
                    var frame = webView.convert(webView.bounds, to: view)
                    if view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
                    let host = Self.host(of: webView)
                    var clip = host.map { $0.convert($0.bounds, to: view) } ?? frame
                    if host != nil, view.isFlipped { clip.origin.y = view.bounds.height - clip.maxY }
                    webSnapshots.append(
                        (image, frame, clip, host?.clippedCornerRadius ?? 0, host?.roundsTopCorners ?? true))
                }
            }
            let size = view.bounds.size
            let image = NSImage(size: size)
            image.lockFocus()
            representation.draw(in: NSRect(origin: .zero, size: size))
            for snapshot in webSnapshots {
                NSGraphicsContext.saveGraphicsState()
                Self.clipPath(snapshot.clip, radius: snapshot.radius, roundsTop: snapshot.roundsTop).addClip()
                snapshot.image.draw(in: snapshot.frame)
                NSGraphicsContext.restoreGraphicsState()
            }
            // A preview card, a sidebar or a bar of tabs floats over the page,
            // whose snapshot was drawn over everything; each goes back on top.
            var floating = floatingCardFrames(in: window, view: view)
            if let card = tabPreviewCardFrame(in: window, view: view) { floating.insert(card, at: 0) }
            for card in floating {
                NSGraphicsContext.saveGraphicsState()
                let radius = Self.tabPreviewCardCornerRadius(in: window)
                NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius).addClip()
                representation.draw(in: NSRect(origin: .zero, size: size))
                NSGraphicsContext.restoreGraphicsState()
            }
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { throw Failure(description: "The snapshot could not be encoded") }
            try png.write(to: url)
            return ["path": url.path, "width": size.width, "height": size.height, "webViews": webSnapshots.count]
        }

        /// A page host's clip in a bottom-up drawing: `rect` rounded to
        /// `radius` at its bottom corners, and at its top ones when `roundsTop`.
        private static func clipPath(_ rect: NSRect, radius: CGFloat, roundsTop: Bool) -> NSBezierPath {
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            guard radius > 0, !roundsTop else { return path }
            let top = NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
            path.append(NSBezierPath(rect: top))
            return path
        }

        /// Where the window's preview card is in `view`, bottom up, while it
        /// shows one.
        private func tabPreviewCardFrame(in window: NSWindow, view: NSView) -> NSRect? {
            guard let context = try? context(), shell.windows?.window(for: context.windowID) === window,
                let card = context.chrome.tabPreviewHover.cardFrame, let content = window.contentView
            else { return nil }
            var frame = content.convert(card, to: view)
            if view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
            return frame
        }

        /// Where the cards floating over the page are in `view`, bottom up,
        /// while a sidebar or a bar of tabs floats: the regions their hover
        /// trackers cover, less the gap each card keeps around itself.
        private func floatingCardFrames(in window: NSWindow, view: NSView) -> [NSRect] {
            guard let context = try? context(), shell.windows?.window(for: context.windowID) === window else {
                return []
            }
            let chrome = context.chrome
            let floatsSidebar = Self.presentation(of: chrome) == .floating
            guard floatsSidebar || chrome.isTopBarRevealed else { return iconTitleFrames(of: chrome, in: view) }
            let inset = BrowserSidebarPresentation.floatingCardInset
            return Self.views(of: BrowserSidebarHoverTrackingView.self, in: view).map { tracker in
                var frame = tracker.convert(tracker.bounds, to: view)
                if view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
                return frame.insetBy(dx: inset, dy: inset)
            }
        }

        /// Where the sidebar of icons shows the title of the icon under the
        /// pointer, in `view`, bottom up: past the column, as wide as the title.
        private func iconTitleFrames(of chrome: BrowserChromeState, in view: NSView) -> [NSRect] {
            guard let shown = chrome.iconSidebarHover.shown else { return [] }
            let font = NSFont.preferredFont(forTextStyle: .callout)
            let width = (shown.title as NSString).size(withAttributes: [.font: font]).width + OdeSpacing.small * 2 + 2
            let column = BrowserIconSidebarMetrics.width
            let x = shown.frame.maxX + (column - shown.frame.width) / 2 + 6
            return [NSRect(x: x, y: view.bounds.height - shown.frame.maxY, width: width, height: shown.frame.height)]
        }

        /// Where `chrome`'s sidebar is, as the window works it out.
        static func presentation(of chrome: BrowserChromeState) -> BrowserSidebarPresentation {
            BrowserSidebarPresentation(
                columnVisibility: chrome.columnVisibility,
                isFloatingSidebarPresented: chrome.isFloatingSidebarPresented, tabLayout: chrome.tabLayout,
                sidebarStyle: chrome.tabLayout.showsTopBar ? .full : chrome.sidebarStyle)
        }

        private static func views<Found: NSView>(of type: Found.Type, in view: NSView) -> [Found] {
            (view as? Found).map { [$0] } ?? view.subviews.flatMap { views(of: type, in: $0) }
        }

        /// The web view's own snapshot, or nil after 1.5 s: a frozen page's
        /// web content never answers, and the window is drawn without it.
        private static func snapshot(of webView: WKWebView) async -> NSImage? {
            final class Once {
                var isDone = false
            }
            let once = Once()
            return await withCheckedContinuation { continuation in
                webView.takeSnapshot(with: nil) { image, _ in
                    MainActor.assumeIsolated {
                        guard !once.isDone else { return }
                        once.isDone = true
                        continuation.resume(returning: image)
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !once.isDone else { return }
                    once.isDone = true
                    continuation.resume(returning: nil)
                }
            }
        }

        /// Hides every ground of each Space backdrop in `view` but the one in
        /// front, answering each hidden layer's opacity to restore.
        private static func hideCoveredGrounds(in view: NSView) -> [(CALayer, Float)] {
            var covered: [(CALayer, Float)] = []
            var pending = [view]
            while let next = pending.popLast() {
                guard String(describing: type(of: next)).hasPrefix("SpaceBackdropBlendView") else {
                    pending.append(contentsOf: next.subviews)
                    continue
                }
                let grounds = next.subviews.compactMap(\.layer).filter { $0.opacity > 0 }
                guard let front = grounds.max(by: { $0.zPosition < $1.zPosition }) else { continue }
                for ground in grounds where ground !== front {
                    covered.append((ground, ground.opacity))
                    ground.opacity = 0
                }
            }
            return covered
        }

        private static func webViews(in view: NSView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews(in:))
        }

        /// The preview card's corner in `window`: a surface's corner of a
        /// macOS 26 window, or of a full-screen one.
        private static func tabPreviewCardCornerRadius(in window: NSWindow) -> CGFloat {
            OdeCornerScale(window: window.styleMask.contains(.fullScreen) ? nil : OdeCornerScale.standard.window)
                .surface
        }

        /// The page host `view` sits in, which clips it.
        private static func host(of view: NSView) -> BrowserWebHostView? {
            var ancestor = view.superview
            while let current = ancestor {
                if let host = current as? BrowserWebHostView { return host }
                ancestor = current.superview
            }
            return nil
        }

        private static func hosts(in view: NSView) -> [BrowserWebHostView] {
            (view as? BrowserWebHostView).map { [$0] } ?? view.subviews.flatMap(hosts(in:))
        }

        /// Every page host in `name`'s window, with the corner it clips its
        /// page to and its frame in the window, for checking that a floating
        /// surface's page follows the surface's corner on either engine.
        func floatingSurfaces(window name: String?) throws -> [String: Any] {
            let window = try window(named: name)
            guard let view = window.contentView?.superview ?? window.contentView else {
                throw Failure(description: "The window has no content")
            }
            let hosts = Self.hosts(in: view).filter { !$0.isHiddenOrHasHiddenAncestor }
            return [
                "hosts": hosts.map { host -> [String: Any] in
                    let frame = host.convert(host.bounds, to: view)
                    return [
                        "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height,
                        "cornerRadius": host.clippedCornerRadius ?? 0,
                        "clips": host.clippedCornerRadius != nil,
                    ]
                }
            ]
        }

        // MARK: - Actions - Descriptions

        private func describe(_ copy: RecoveryCopy) -> [String: Any] {
            [
                "name": copy.name, "takenAt": copy.takenAt.timeIntervalSince1970, "spaces": copy.spaces,
                "tabs": copy.tabs, "held": copy.held, "beforeRestore": copy.beforeRestore,
                "updateTo": copy.updateTo ?? "",
            ]
        }

        private func describe(_ report: BrowserCrashReport) -> [String: Any] {
            [
                "id": report.id, "kind": String(describing: report.kind),
                "occurredAt": report.occurredAt.timeIntervalSince1970,
                "summary": report.summary,
            ]
        }
    }

    extension BrowserMacHarness {
        // MARK: - Actions - Demo content and capture

        /// Sets up Spaces as `specs` describe, for pictures of the app: the
        /// Spaces setup made are reused in order and emptied, more are
        /// added, and each gets its name, glyph, color preset, pinned tabs,
        /// saved tabs, open tabs and one folder, open or saved. Only public
        /// addresses are opened.
        fileprivate func setupDemo(_ specs: [[String: Any]]) async throws -> [String: Any] {
            let browser = try context().browser
            var ids = browser.spaceModels.map(\.id)
            while ids.count < specs.count {
                let before = Set(browser.spaceModels.map(\.id))
                _ = try? browser.addSpace()
                try? await Task.sleep(for: .milliseconds(300))
                guard let added = browser.spaceModels.map(\.id).first(where: { !before.contains($0) }) else {
                    throw Failure(description: "A Space could not be added")
                }
                ids.append(added)
            }
            for (spec, id) in zip(specs, ids) {
                browser.selectSpace(id)
                try? await Task.sleep(for: .milliseconds(250))
                guard let space = browser.spaceModel(id) else { continue }
                for folder in space.folders.models { _ = browser.deleteFolder(folder.id, in: id) }
                for tab in space.tabs.models where tab.placement.isDurable {
                    _ = browser.moveTab(tab.id, from: id, to: .current)
                }
                // Closing a loaded tab waits for its page to agree to go, which
                // in a window nobody sees does not always finish; demo pages
                // need no say.
                _ = browser.clearSessionTabs(in: id)
                try? await Task.sleep(for: .milliseconds(250))
                let preset = SpaceColorPreset.all.first { $0.name == spec["preset"] as? String } ?? .azure
                browser.updateSpaceIdentity(
                    id, name: spec["name"] as? String ?? "Space", symbol: spec["symbol"] as? String ?? "circle.fill",
                    accent: space.settings.accent)
                var branding = preset.branding
                branding.showsTexture = spec["grain"] as? Bool ?? false
                browser.updateSpaceBranding(branding, in: id)
                for address in spec["pinned"] as? [String] ?? [] {
                    guard let url = URL(string: address), let tabID = browser.openNewTab(url: url) else { continue }
                    browser.pinTab(tabID)
                    try? await Task.sleep(for: .milliseconds(150))
                }
                for address in spec["saved"] as? [String] ?? [] {
                    guard let url = URL(string: address), let tabID = browser.openNewTab(url: url) else { continue }
                    browser.saveTab(tabID)
                    try? await Task.sleep(for: .milliseconds(150))
                }
                if let folder = spec["folder"] as? [String: Any] {
                    var tabIDs: [UUID] = []
                    for address in folder["urls"] as? [String] ?? [] {
                        if let url = URL(string: address), let tabID = browser.openNewTab(url: url) {
                            tabIDs.append(tabID)
                        }
                    }
                    if let shown = browser.shownSpace, !tabIDs.isEmpty {
                        let assignment = BrowserSpaceRuntimeAssignment(space: shown)
                        let folderID = browser.createTabFolder(
                            tabIDs, titled: folder["title"] as? String ?? "Folder", matching: assignment)
                        if let folderID, folder["saved"] as? Bool ?? false {
                            browser.moveFolder(folderID, matching: assignment, to: .saved)
                        }
                    }
                }
                for address in spec["tabs"] as? [String] ?? [] {
                    if let url = URL(string: address) { _ = browser.openNewTab(url: url) }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            return [
                "spaces": browser.spaceModels.map { space -> [String: Any] in
                    [
                        "name": space.settings.name, "tabs": space.tabs.models.count,
                        "folders": space.folders.models.count,
                    ]
                }
            ]
        }

        /// With `on`, puts `name`'s window beneath every other window with
        /// one point on the main display and full opacity, where the window
        /// server draws it whole for `screencapture -l` and nobody sees it,
        /// at the content size asked for; without, puts it back.
        fileprivate func presentForCapture(window name: String?, on: Bool, width: Double?, height: Double?) throws
            -> [String: Any]
        {
            let window = try window(named: name)
            if on {
                if capturePlacements[window.windowNumber] == nil {
                    capturePlacements[window.windowNumber] = BrowserMacHarnessCapturePlacement(
                        origin: window.frame.origin, level: window.level, alpha: window.alphaValue,
                        ignoresMouseEvents: window.ignoresMouseEvents)
                }
                if let width, let height { window.setContentSize(NSSize(width: width, height: height)) }
                guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                    throw Failure(description: "No display is attached")
                }
                window.ignoresMouseEvents = true
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                window.setFrameOrigin(
                    NSPoint(
                        x: screen.frame.minX - window.frame.width + 1, y: screen.frame.minY - window.frame.height + 1))
                window.alphaValue = 1
                Self.drawPagesWhileCovered(true, in: window)
                window.displayIfNeeded()
            } else if let placement = capturePlacements.removeValue(forKey: window.windowNumber) {
                window.alphaValue = placement.alpha
                window.level = placement.level
                window.setFrameOrigin(placement.origin)
                window.ignoresMouseEvents = placement.ignoresMouseEvents
                Self.drawPagesWhileCovered(false, in: window)
            }
            return [
                "windowNumber": window.windowNumber, "width": window.frame.width, "height": window.frame.height,
                "scale": window.backingScaleFactor,
            ]
        }

        /// WebKit stops drawing the pages of a window other windows cover, and
        /// a window presented for capture always is covered, so its pages
        /// ignore that until it goes back.
        private static func drawPagesWhileCovered(_ drawing: Bool, in window: NSWindow) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
            for webView in webViews(in: window.contentView ?? NSView()) where webView.responds(to: selector) {
                unsafeBitCast(webView.method(for: selector), to: Setter.self)(webView, selector, !drawing)
            }
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
    }

#endif
