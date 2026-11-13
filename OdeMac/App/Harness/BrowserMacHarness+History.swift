#if DEBUG || ODE_REVIEW_BUILD

    import AppKit

    /// The harness's history commands: bring a browser profile's history in
    /// the way an import from that browser reads it, and read the shown
    /// Space's history the way the History list does, timing both.
    extension BrowserMacHarness {
        // MARK: - Actions - Imports

        /// Reads the history of the `source` browser profile in the folder
        /// `profile`, as an import reads it, imports it as a new Space and
        /// shows that Space. Answers how many addresses the Space itself
        /// keeps and how long the read and the import took, in milliseconds.
        func importHistory(_ arguments: [String: Any]) throws -> [String: Any] {
            let browser = try context().browser
            guard let name = arguments["source"] as? String,
                let source = ImportSource.all.first(where: { $0.name == name }),
                let folder = arguments["profile"] as? String
            else { throw Failure(description: "importHistory takes a source and a profile folder") }
            let profile = ImportProfile(
                id: "harness", name: arguments["name"] as? String ?? source.title, bookmarksPath: nil, sessionPath: nil,
                profilePath: folder)
            let clock = ContinuousClock()
            let started = clock.now
            let read: ImportedSpaces
            do {
                read = try browser.core.query(ReadImport(source: source, profiles: [profile], readID: nil))
            } catch {
                throw Failure(description: "The core could not read the history: \(error)")
            }
            let readTime = clock.now - started
            let before = Set(browser.spaceModels.map(\.id))
            do {
                try browser.importSpaces(read.spaces)
            } catch {
                throw Failure(description: "The core refused the import: \(error)")
            }
            let importTime = clock.now - started - readTime
            guard let imported = browser.spaceModels.first(where: { !before.contains($0.id) }) else {
                throw Failure(description: "The import brought no Space")
            }
            browser.selectSpace(imported.id)
            return [
                "spaceID": imported.id.uuidString, "sessionEntries": imported.history.entries.count,
                "readMs": Self.milliseconds(readTime), "importMs": Self.milliseconds(importTime),
            ]
        }

        // MARK: - Actions - Reading

        /// Reads the shown Space's history as the History list does, `runs`
        /// times, for `text`, at most `limit` addresses, once `settle`
        /// seconds passed for the history store to finish writing. Answers
        /// how many it found, whether more follow, the newest few and the
        /// median and 95th percentile read time in milliseconds.
        func historyList(_ arguments: [String: Any]) async throws -> [String: Any] {
            let browser = try context().browser
            guard let space = browser.shownSpace else { throw Failure(description: "No Space is shown") }
            if let settle = arguments["settle"] as? Double { try? await Task.sleep(for: .seconds(settle)) }
            let reader = BrowserHistoryReader(core: browser.core, workspaceID: browser.family.workspaceID)
            let text = arguments["text"] as? String ?? ""
            let limit = arguments["limit"] as? Int ?? BrowserHistoryReader.pageSize
            let runs = max(arguments["runs"] as? Int ?? 1, 1)
            let spaceID = space.id
            let (answer, times) = try await Task.detached(priority: .userInitiated) {
                let clock = ContinuousClock()
                var answer: HistoryPlaces?
                var times: [Double] = []
                for _ in 0..<runs {
                    let started = clock.now
                    answer = try reader.places(in: spaceID, matching: text, limit: limit)
                    times.append(Self.milliseconds(clock.now - started))
                }
                return (answer, times.sorted())
            }.value
            guard let answer else { throw Failure(description: "The core refused to read the history") }
            return [
                "count": answer.places.count, "hasMore": answer.hasMore,
                "newest": answer.places.prefix(5).map { ["url": $0.url, "title": $0.title, "visits": $0.visitCount] },
                "medianMs": times[times.count / 2], "p95Ms": times[min(times.count - 1, times.count * 95 / 100)],
            ]
        }

        nonisolated static func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        }
    }

#endif
