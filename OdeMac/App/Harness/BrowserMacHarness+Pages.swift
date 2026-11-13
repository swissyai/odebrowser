#if DEBUG || ODE_REVIEW_BUILD

    import AppKit

    /// The harness's page and extension commands: run a reader in the shown
    /// page's main document and answer what it returned, capture the shown
    /// page through its engine, install Chrome Web Store extensions into the
    /// shown Space as an import does, list them, and offer a chord to the
    /// shown page's extensions as an unclaimed shortcut.
    extension BrowserMacHarness {
        // MARK: - Actions - Pages

        /// Runs `script`, the body of an async function that returns JSON
        /// text, in the shown page's main document, in a script world the
        /// page cannot see, through whichever engine shows it.
        func probePage(_ script: String, timeout: Double) async throws -> [String: Any] {
            guard let page = try context().pages.activePage, let document = page.previewDocument else {
                throw Failure(description: "The shown tab has no page that runs a reader")
            }
            guard let answer = await document.read(script, timeout: .seconds(timeout)) else {
                throw Failure(description: "The page did not answer")
            }
            let value = try JSONSerialization.jsonObject(with: answer, options: .fragmentsAllowed)
            return ["result": value, "engine": page.webKitAdapter == nil ? "chromium" : "webkit"]
        }

        /// Delivers input to the shown page through its engine, as an agent's
        /// tools do: a click at `click` ([x, y] in CSS pixels from the page's
        /// top left), `text` typed into what has focus, or `key` (a named
        /// key) pressed with `modifiers` (`command`, `shift`, `option`,
        /// `control`).
        func inputPage(_ arguments: [String: Any]) async throws -> [String: Any] {
            guard let page = try context().pages.activePage else { throw Failure(description: "No page is shown") }
            let input: EnginePageInput
            if let point = arguments["click"] as? [Double], point.count == 2 {
                input = .click(at: PagePoint(x: point[0], y: point[1]))
            } else if let text = arguments["text"] as? String {
                input = .type(text)
            } else if let name = arguments["key"] as? String, let key = BrowserAgentKey.named(name) {
                var modifiers: KeyModifiers = []
                for flag in arguments["modifiers"] as? [String] ?? [] {
                    switch flag {
                    case "command": modifiers.insert(.command)
                    case "shift": modifiers.insert(.shift)
                    case "option": modifiers.insert(.option)
                    case "control": modifiers.insert(.control)
                    default: throw Failure(description: "Unknown modifier \(flag)")
                    }
                }
                input = .press(key.pageKey, modifiers: modifiers)
            } else {
                throw Failure(description: "inputPage needs click, text or key")
            }
            guard let delivered = await page.enginePage.deliver(input, timeout: .seconds(5)) else {
                throw Failure(description: "The engine did not deliver the input")
            }
            return ["delivered": String(describing: delivered)]
        }

        /// Captures what the shown page's view shows, through its engine, as
        /// a PNG beside the session; the client copies it out.
        func capturePage(named name: String) async throws -> [String: Any] {
            guard !name.isEmpty, !name.contains("/") else {
                throw Failure(description: "capturePage needs a file name")
            }
            guard let page = try context().pages.activePage else { throw Failure(description: "No page is shown") }
            let data: Data? = await withCheckedContinuation { continuation in
                page.enginePage.capture { continuation.resume(returning: $0) }
            }
            guard let data else { throw Failure(description: "The page showed nothing to capture") }
            let folder = directory.appendingPathComponent("Snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name + ".png")
            try data.write(to: url)
            return ["path": url.path, "bytes": data.count]
        }

        /// The sheet the browser window shows, such as an engine's question,
        /// with its text and buttons; with `press`, presses that button.
        func browserSheet(press button: Int?) throws -> [String: Any] {
            guard let sheet = try targetWindow().attachedSheet else { return ["shown": false] }
            func texts(in view: NSView) -> [String] {
                view.subviews.flatMap { subview -> [String] in
                    if let field = subview as? NSTextField, !field.stringValue.isEmpty { return [field.stringValue] }
                    return texts(in: subview)
                }
            }
            func buttons(in view: NSView) -> [NSButton] {
                view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons(in: $0) }
            }
            let found = sheet.contentView.map(buttons(in:)) ?? []
            let titles = found.map(\.title).filter { !$0.isEmpty }
            if let button, let target = found.filter({ !$0.title.isEmpty }).dropFirst(button).first {
                target.performClick(nil)
            }
            return ["shown": true, "texts": sheet.contentView.map(texts(in:)) ?? [], "buttons": titles]
        }

        /// What Ode's own passwords hold for the shown page: a pending fill
        /// request and a pending offer to save, and the extension that keeps
        /// the page's passwords instead, when one does.
        func credentialState() throws -> [String: Any] {
            guard let page = try context().pages.activePage else { throw Failure(description: "No page is shown") }
            let state = page.credentialState
            return [
                "fillRequest": state.fillRequest != nil, "saveCandidate": state.saveCandidate != nil,
                "enabled": page.isCredentialAccessEnabled, "passwordExtension": page.passwordExtension ?? "",
            ]
        }

        /// What the window and the shown page make of a page's fullscreen:
        /// the fullscreen requests the window recorded instead of carrying
        /// out, whether the page shows alone, and what the window shows.
        func fullscreenState() throws -> [String: Any] {
            let context = try context()
            let window = try targetWindow()
            let page = context.pages.activePage
            return [
                "requests": BrowserMacHarnessWindows.fullscreenRequests,
                "pageAlone": page?.isContentFullscreen ?? false,
                "fullscreenPages": context.pages.livePages.filter(\.isContentFullscreen).count,
                "windowFullscreen": window.styleMask.contains(.fullScreen),
                "sidebarVisible": context.chrome.columnVisibility != .detailOnly,
                "commandBarOpen": context.chrome.isCommandPalettePresented,
                "firstResponder": window.firstResponder.map { String(describing: type(of: $0)) } ?? "",
                "pageHasFocus": BrowserWebHostView.isPageContent(window.firstResponder),
            ]
        }

        // MARK: - Actions - Focus

        /// Turns Focus's hidden feeds on or off, sets a site's daily limit in
        /// minutes (0 for none), and adds seconds already spent on it today,
        /// then reports what Focus holds and whether the shown page is paused.
        func focus(_ arguments: [String: Any]) throws -> [String: Any] {
            let preferences = BrowserAppPreferenceStore.shared
            if let hidesFeeds = arguments["hidesFeeds"] as? Bool { preferences.focus.hidesFeeds = hidesFeeds }
            if let site = arguments["site"] as? String {
                if let minutes = arguments["minutes"] as? Int {
                    preferences.focus = preferences.focus.limiting(site, to: minutes > 0 ? minutes : nil)
                }
                if let seconds = arguments["spent"] as? Double {
                    BrowserFocusTimeKeeper.shared.count(seconds, on: site)
                }
            }
            let page = try context().pages.activePage
            let site = BrowserSite.of(page?.live.displayURL)
            let limit = preferences.focus.limit(for: site)
            return [
                "hidesFeeds": preferences.focus.hidesFeeds,
                "limits": preferences.focus.limits.map { ["site": $0.site, "minutes": $0.minutesPerDay] },
                "site": site ?? "", "spent": site.map { BrowserFocusTimeKeeper.shared.seconds(on: $0) } ?? 0,
                "paused": site.map { BrowserFocusTimeKeeper.shared.isPaused($0, limit: limit) } ?? false,
                "focusCSS": page?.boost.focusStyles[site ?? ""] ?? "",
                "pauseShown": site.map { BrowserFocusTimeKeeper.shared.pausedOnScreen.contains($0) } ?? false,
            ]
        }

        /// Shows the pause a site wears once its daily limit is used, in a
        /// window titled "Focus Pause" to snapshot: the browser window's
        /// snapshot draws its pages over everything above them.
        func showFocusPause(site: String, minutes: Int) -> [String: Any] {
            show(
                BrowserFocusPauseView(
                    site: site, limit: SiteTimeLimit(site: site, minutesPerDay: minutes), extend: {}, closeTab: {}),
                titled: "Focus Pause", width: 560)
        }

        // MARK: - Actions - Quick Windows

        /// Opens `address` in a Quick Window on the shown Space, as a link
        /// from another app opens there.
        func openQuickWindow(_ address: String) throws -> [String: Any] {
            guard let url = URL(string: address) else { throw Failure(description: "openQuickWindow needs a URL") }
            let context = try context()
            guard let space = context.browser.shownSpace, let windows = shell.windows else {
                throw Failure(description: "No Space is shown")
            }
            windows.openQuickWindow(
                BrowserQuickWindowRequest(
                    url: url, spaceAssignment: BrowserSpaceRuntimeAssignment(space: space),
                    targetWindowID: context.windowID))
            return ["space": space.settings.name]
        }

        /// Shows the Quick Window's destination picker for the shown window's
        /// Spaces in a window titled "Quick Window Spaces" to snapshot.
        func showQuickWindowPicker() throws -> [String: Any] {
            let browser = try context().browser
            guard let shown = browser.shownSpace else { throw Failure(description: "No Space is shown") }
            return show(
                BrowserQuickWindowSpacePicker(
                    spaces: browser.spaceModels.map(\.identity), selectedSpaceID: shown.id, selectSpace: { _ in },
                    addSpace: {}),
                titled: "Quick Window Spaces", width: 280)
        }

        // MARK: - Actions - Extensions

        /// Installs each Chrome Web Store extension `items` names into the
        /// shown Space, as an import's reviewed extensions install.
        func installExtensions(_ items: [[String: Any]]) throws -> [String: Any] {
            guard let installer = shell.engineHost.importedExtensionInstaller else {
                throw Failure(description: "This engine runs no extensions")
            }
            guard let space = try context().browser.shownSpace else { throw Failure(description: "No Space is shown") }
            let installs = items.compactMap { item -> ImportExtensionInstall? in
                guard let id = item["id"] as? String else { return nil }
                return ImportExtensionInstall(
                    extensionID: id, name: item["name"] as? String ?? id, iconPath: nil, spaceIDs: [space.id])
            }
            installer.installImported(installs)
            return ["queued": installs.map(\.extensionID), "spaceID": space.id.uuidString]
        }

        /// Offers `key`, such as `cmd+shift+l`, to the shown page's engine as
        /// a chord no Ode command claimed, and answers whether it took it.
        func offerUnclaimedShortcut(_ key: String) throws -> [String: Any] {
            guard let page = try context().pages.activePage else { throw Failure(description: "No page is shown") }
            let window = try targetWindow()
            guard let event = Self.keyEvent(key, in: window) else { throw Failure(description: "Unknown key \(key)") }
            return ["taken": shell.engineHost.handleUnclaimedShortcut(event, page: page)]
        }

        /// The key-down event for a chord written as modifiers and one key,
        /// such as `cmd+shift+l` or `cmd+.`.
        static func keyEvent(_ chord: String, in window: NSWindow) -> NSEvent? {
            var parts = chord.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            guard var key = parts.popLast() else { return nil }
            if key.isEmpty, parts.last == "" {
                parts.removeLast()
                key = "+"
            }
            var flags: NSEvent.ModifierFlags = []
            for part in parts {
                switch part {
                case "cmd": flags.insert(.command)
                case "shift": flags.insert(.shift)
                case "opt", "alt": flags.insert(.option)
                case "ctrl": flags.insert(.control)
                default: return nil
                }
            }
            let codes: [String: UInt16] = [
                "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
                "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
                "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
                "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
                ".": 47, "space": 49, "escape": 53,
            ]
            guard let code = codes[key] else { return nil }
            let characters = key == "space" ? " " : key == "escape" ? "\u{1b}" : key
            let shifted = flags.contains(.shift) ? characters.uppercased() : characters
            return NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: shifted, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
        }
    }

    #if ODE_CHROMIUM_HOST
        extension BrowserMacHarness {
            /// What the shown Space's engine profile has installed.
            func installedExtensions() async throws -> [String: Any] {
                guard let space = try context().browser.shownSpace?.identity else {
                    throw Failure(description: "No Space is shown")
                }
                let store = ChromiumComposition.extensions
                // The core lists the Space's extensions once the engine read
                // its profile; until then the list is empty.
                store.load(space)
                store.refresh()
                let pinned = store.pinnedActions(for: space, page: try context().pages.activePage?.chromiumPage)
                return [
                    "profileID": space.profileID.uuidString,
                    "extensions": (store.installed(in: space) ?? []).map { item -> [String: Any] in
                        ["id": item.id, "name": item.name, "version": item.version, "enabled": item.enabled]
                    },
                    "pinned": pinned.map(\.id),
                    "installing": store.installation?.extensionID ?? "",
                ]
            }
        }
    #else
        extension BrowserMacHarness {
            func installedExtensions() async throws -> [String: Any] { ["extensions": []] }
        }
    #endif

#endif
