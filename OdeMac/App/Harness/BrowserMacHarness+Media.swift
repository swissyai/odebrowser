#if DEBUG || ODE_REVIEW_BUILD

    import AppKit

    /// The harness's player commands: give a tab a player without playing
    /// anything, report the players, and go back to the playing tab as the
    /// Tabs menu does. Nothing here makes a sound, and the system's Now
    /// Playing never hears of a harness launch.
    extension BrowserMacHarness {
        // MARK: - Actions - Media

        /// Gives the tab whose address or title holds `text`, in any Space of
        /// the window, a player as its page would report one: `title`,
        /// `artist`, playing or paused, `elapsed` of `duration` seconds, and
        /// artwork unless `artwork` is false.
        func stageMediaSession(_ arguments: [String: Any]) throws -> [String: Any] {
            guard let application = shell.application else { throw Failure(description: "The browser is not running") }
            let text = arguments["text"] as? String ?? ""
            let browser = try context().browser
            guard
                let (space, tab) = browser.spaceModels.lazy.compactMap({ space in
                    space.tabs.models.first { ($0.url ?? "").contains(text) || $0.title.contains(text) }
                        .map { (space, $0) }
                }).first
            else { throw Failure(description: "No tab matches \(text)") }
            let playing = arguments["playing"] as? Bool ?? true
            let duration = arguments["duration"] as? Double
            mediaSequence &+= 1
            let event = BrowserMediaSessionPageEvent(
                documentIdentifier: "harness-\(tab.id.uuidString)", sequence: mediaSequence,
                location: tab.url ?? "https://player.example/", isInvalidated: false, hasActiveSession: true,
                title: arguments["title"] as? String, artist: arguments["artist"] as? String,
                album: arguments["album"] as? String,
                artworkData: arguments["artwork"] as? Bool == false ? nil : Self.stagedArtwork,
                playbackState: playing ? .playing : .paused, isAudible: playing, isMuted: false,
                availableActions: [.play, .pause, .previousTrack, .nextTrack],
                position: duration.map {
                    BrowserMediaSessionPosition(
                        elapsed: arguments["elapsed"] as? Double ?? 0, duration: $0, rate: playing ? 1 : 0,
                        reportedAt: Date())
                })
            application.mediaSessions.receive(
                event, owner: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
                fallbackTitle: tab.title, endpoint: mediaEndpoint)
            return ["tabID": tab.id.uuidString, "space": space.settings.name]
        }

        /// Every player, newest last, with the actions its controls sent.
        func mediaSessions() throws -> [String: Any] {
            guard let application = shell.application else { throw Failure(description: "The browser is not running") }
            return [
                "sessions": application.mediaSessions.sessions.map { session -> [String: Any] in
                    [
                        "tabID": session.owner.tabID.uuidString, "title": session.mediaDisplayTitle,
                        "playing": session.playbackState == .playing,
                        "fraction": session.position?.fraction(at: Date()) ?? -1,
                    ]
                },
                "actions": mediaEndpoint.actions.map(\.rawValue),
            ]
        }

        /// Where Back to Playing Tab goes from the window the person used.
        func mediaReturnRoute() throws -> [String: Any] {
            guard let windows = shell.windows, let sessions = shell.application?.mediaSessions.sessions,
                let target = BrowserMediaReturnRoute.target(in: sessions),
                let route = windows.mediaReturnRoute(to: target.owner, from: try context().windowID)
            else { throw Failure(description: "No player has a tab to go back to") }
            return [
                "windowID": route.windowID.uuidString, "tabID": route.tabID.uuidString,
                "bringsWindowForward": route.bringsWindowForward, "unlocksSpace": route.unlocksSpace,
            ]
        }

        /// Runs Back to Playing Tab as the Tabs menu does, then reports the
        /// shown Space and tab. It runs only while the route stays in the
        /// window the person used, since bringing another forward is theirs.
        func backToPlayingTab() async throws -> [String: Any] {
            guard try mediaReturnRoute()["bringsWindowForward"] as? Bool == false else {
                throw Failure(description: "Back to Playing Tab would bring another window forward")
            }
            guard BrowserMacApplicationAction.runFromMenu(BrowserMacApplicationAction.backToPlayingTab.name) else {
                throw Failure(description: "The Tabs menu does not offer Back to Playing Tab")
            }
            try? await Task.sleep(for: .milliseconds(300))
            let context = try context()
            return [
                "space": context.browser.shownSpace?.settings.name ?? "",
                "tabID": context.browser.shownTab?.id.uuidString ?? "",
                "presented": context.pages.presentedTabIDs.map(\.uuidString),
            ]
        }

        /// A square of warm color the staged players wear as artwork.
        private static let stagedArtwork: Data? = {
            let size = NSSize(width: 256, height: 256)
            let image = NSImage(size: size, flipped: false) { bounds in
                NSGradient(
                    colors: [
                        NSColor(srgbRed: 0.93, green: 0.45, blue: 0.32, alpha: 1),
                        NSColor(srgbRed: 0.42, green: 0.22, blue: 0.55, alpha: 1),
                    ])?.draw(in: bounds, angle: -60)
                NSColor(white: 1, alpha: 0.85).setFill()
                NSBezierPath(ovalIn: bounds.insetBy(dx: 92, dy: 92)).fill()
                return true
            }
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }()
    }

#endif
