#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import IOSurface
    import QuartzCore
    import WebKit

    /// The harness's frame sampler: what the shown page's area of the browser
    /// window holds at each display frame while a navigation, a tab or Space
    /// switch or a launch runs, read from the window's own layers, so a run
    /// can count the frames that show neither the page before nor the page
    /// after. The window stays off the screens; its pages keep drawing.
    ///
    /// Each frame draws the window without the page's host, then lays the
    /// host over it, read straight from the surfaces the engine handed Core
    /// Animation and read again only when the host's layers changed. That
    /// keeps a frame to a few milliseconds when the surfaces are plain:
    /// WebKit's lossless tile compression off
    /// (`ODE_TEST_HARNESS_WEBKIT_FEATURES=IOSurfaceLosslessCompressionEnabled=disabled`)
    /// and Chromium's frames in this process
    /// (`--disable-features=RemoteCoreAnimationAPI`). Otherwise the host is
    /// drawn, which is slower but just as faithful, and Chromium's frames drawn
    /// in its GPU process show only its background.
    extension BrowserMacHarness {
        // MARK: - Types

        /// One sampled frame: when it was read, the page area's pixels, and
        /// what the shown page was doing.
        struct SampledFrame {
            let milliseconds: Double
            let pixels: [UInt8]
            let state: String
            let cost: Double
        }

        // MARK: - Actions - Sampling

        /// Samples the shown page's area at the main display's rate for
        /// `duration` seconds, running `action` `lead` seconds in, and saves
        /// the frames beside the session as `name.rgba` (rows top down, RGBA)
        /// with `name.json` describing them and `name.png`, every frame side
        /// by side.
        func sampleFrames(_ arguments: [String: Any]) async throws -> [String: Any] {
            guard let name = arguments["name"] as? String, !name.isEmpty, !name.contains("/") else {
                throw Failure(description: "sampleFrames needs a file name")
            }
            let duration = arguments["duration"] as? Double ?? 2
            let lead = arguments["lead"] as? Double ?? 0.25
            let columns = arguments["columns"] as? Int ?? 48
            let rows = arguments["rows"] as? Int ?? 30
            let action = arguments["action"] as? [String: Any] ?? [:]
            let readsLayers = (arguments["mode"] as? String ?? "layers") == "layers"
            let window = try targetWindow()
            var sampler = BrowserMacHarnessLayerSampler()
            var hostPixels = HostPixels()
            var slowFrames = 0
            var readerError = -1
            var readerMeanError = -1.0
            keepPagesDrawing(in: window)
            var frames: [SampledFrame] = []
            var area = (arguments["area"] as? [Double]).flatMap { values in
                values.count == 4 ? CGRect(x: values[0], y: values[1], width: values[2], height: values[3]) : nil
            }
            var finished = false
            var actionAt: Double?
            var actionResult: [String: Any] = [:]
            let ticker = BrowserMacHarnessFrameTicker()
            let start = CACurrentMediaTime()
            let rate = Double(NSScreen.main?.maximumFramesPerSecond ?? 60)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                ticker.tick = { [weak self] link in
                    guard let self, !finished else { return }
                    let elapsed = CACurrentMediaTime() - start
                    if actionAt == nil, elapsed >= lead {
                        actionAt = elapsed * 1000
                        actionResult = (try? self.perform(frameAction: action)) ?? ["error": "action failed"]
                    }
                    self.keepPagesDrawing(in: window)
                    if area == nil { area = self.pageArea(in: window) }
                    if let area {
                        if frames.isEmpty, readsLayers,
                            let composited = Self.composite(
                                window: window, area: area, columns: columns, rows: rows, sampler: &sampler,
                                host: &hostPixels)
                        {
                            // How far reading the surfaces strays from drawing the
                            // layers, once, as the run's check on the reader.
                            let drawn = Self.render(window: window, area: area, columns: columns, rows: rows)
                            readerError = zip(composited, drawn).map { abs(Int($0) - Int($1)) }.max() ?? 0
                            readerMeanError =
                                Double(zip(composited, drawn).map { abs(Int($0) - Int($1)) }.reduce(0, +))
                                / Double(max(1, drawn.count))
                        }
                        let began = CACurrentMediaTime()
                        var pixels: [UInt8]
                        if readsLayers,
                            let composited = Self.composite(
                                window: window, area: area, columns: columns, rows: rows, sampler: &sampler,
                                host: &hostPixels)
                        {
                            pixels = composited
                        } else {
                            if readsLayers { slowFrames += 1 }
                            pixels = Self.render(window: window, area: area, columns: columns, rows: rows)
                        }
                        frames.append(
                            SampledFrame(
                                milliseconds: elapsed * 1000, pixels: pixels, state: self.frameState(),
                                cost: (CACurrentMediaTime() - began) * 1000))
                    }
                    if elapsed >= duration {
                        finished = true
                        ticker.stop()
                        continuation.resume()
                    }
                }
                ticker.start(rate: rate)
            }
            let folder = directory.appendingPathComponent("Snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var raw = Data(capacity: frames.count * columns * rows * 4)
            for frame in frames { raw.append(contentsOf: frame.pixels) }
            try raw.write(to: folder.appendingPathComponent(name + ".rgba"))
            let meta: [String: Any] = [
                "columns": columns, "rows": rows, "rate": rate, "actionAt": actionAt ?? -1, "action": actionResult,
                "slowFrames": slowFrames, "readerError": readerError, "readerMeanError": readerMeanError,
                "hostReads": hostPixels.reads, "hostDraws": hostPixels.draws,
                "slowReason": BrowserMacHarnessLayerSampler.lastFailure ?? "",
                "area": area.map { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] } ?? [:],
                "frames": frames.map { ["t": $0.milliseconds, "state": $0.state, "cost": $0.cost] },
            ]
            let json = try JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys])
            try json.write(to: folder.appendingPathComponent(name + ".json"))
            if let sheet = Self.contactSheet(frames, columns: columns, rows: rows) {
                try sheet.write(to: folder.appendingPathComponent(name + ".png"))
            }
            return [
                "path": folder.appendingPathComponent(name).path, "frames": frames.count,
                "medianCost": frames.map(\.cost).sorted().dropFirst(frames.count / 2).first ?? 0,
            ]
        }

        /// Runs the sampled moment's action through the path its menu, key or
        /// link takes.
        private func perform(frameAction action: [String: Any]) throws -> [String: Any] {
            let kind = action["kind"] as? String ?? "none"
            let context = try context()
            let url = (action["url"] as? String).flatMap(URL.init(string:))
            switch kind {
            case "none":
                break
            case "command":
                guard let command = ShortcutCommand.named(action["name"] as? String) else {
                    throw Failure(description: "No such command")
                }
                try commands().perform(command)
            case "load":
                guard let url, let page = context.pages.activePage else { throw Failure(description: "No page") }
                page.corePage.load(url)
            case "link":
                guard let url, let document = context.pages.activePage?.previewDocument else {
                    throw Failure(description: "No page")
                }
                let script = "location.href = \(Self.javaScriptString(url.absoluteString)); return 'true';"
                Task { _ = await document.read(script, timeout: .seconds(2)) }
            case "click":
                // A click the engine delivers as the person's, which a page
                // counts as its user's activation.
                guard let page = context.pages.activePage else { throw Failure(description: "No page") }
                let point = PagePoint(x: action["x"] as? Double ?? 0, y: action["y"] as? Double ?? 0)
                Task { _ = await page.enginePage.deliver(.click(at: point), timeout: .seconds(2)) }
            case "openTab":
                guard let url, let tabID = context.browser.openNewTab(url: url) else {
                    throw Failure(description: "No tab opened")
                }
                return ["tabID": tabID.uuidString]
            case "selectTab":
                let text = action["text"] as? String ?? ""
                guard
                    let tab = context.browser.shownSpace?.tabs.models.first(where: {
                        ($0.url ?? "").contains(text) || $0.title.contains(text)
                    })
                else { throw Failure(description: "No tab matches") }
                context.browser.selectTab(tab.id)
                return ["tabID": tab.id.uuidString]
            default:
                throw Failure(description: "Unknown action \(kind)")
            }
            return ["kind": kind]
        }

        /// Puts the shown tab's neighbour `text` names to sleep, as the pool
        /// does once nobody has shown it for a while.
        func sleepTab(matching text: String) throws -> [String: Any] {
            let context = try context()
            guard
                let tab = context.browser.shownSpace?.tabs.models.first(where: {
                    ($0.url ?? "").contains(text) || $0.title.contains(text)
                })
            else { throw Failure(description: "No tab matches \(text)") }
            guard context.browser.shownTab?.id != tab.id else { throw Failure(description: "The tab is shown") }
            context.pages.host.unloadPage(for: tab.id)
            return ["tabID": tab.id.uuidString]
        }

        // MARK: - Actions - Reading the window

        /// Where the shown page's view sits in the window's frame view: its
        /// host's bounds, inset from the corners and the loading bar.
        private func pageArea(in window: NSWindow) -> CGRect? {
            guard let frameView = window.contentView?.superview ?? window.contentView,
                let host = Self.shownHost(in: frameView)
            else { return nil }
            let frame = host.convert(host.bounds, to: frameView)
            return frame.insetBy(dx: frame.width * 0.06, dy: frame.height * 0.06)
        }

        /// The page host the window presents, the largest one on show.
        private static func shownHost(in view: NSView) -> BrowserWebHostView? {
            func hosts(_ view: NSView) -> [BrowserWebHostView] {
                (view as? BrowserWebHostView).map { [$0] } ?? view.subviews.flatMap(hosts)
            }
            return hosts(view).filter { !$0.isHiddenOrHasHiddenAncestor && $0.presentation == .presented }
                .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        }

        /// Draws `area` of `window`'s layers into `columns` by `rows` pixels,
        /// top row first.
        private static func render(window: NSWindow, area: CGRect, columns: Int, rows: Int) -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
            guard let frameView = window.contentView?.superview ?? window.contentView, let layer = frameView.layer,
                let space = CGColorSpace(name: CGColorSpace.sRGB)
            else { return pixels }
            // The window's frame view is not flipped, so the area and the
            // context share a bottom-left origin.
            pixels.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                        bytesPerRow: columns * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.interpolationQuality = .low
                context.scaleBy(x: CGFloat(columns) / area.width, y: CGFloat(rows) / area.height)
                context.translateBy(x: -area.minX, y: -area.minY)
                layer.render(in: context)
            }
            return pixels
        }

        /// The page host's own pixels from the last frame that drew them,
        /// and what they looked like then.
        struct HostPixels {
            var signature: Int?
            var pixels: [UInt8] = []
            /// How many frames read the host from its surfaces, and how many
            /// had to draw it.
            var reads = 0
            var draws = 0
        }

        /// Draws `area` as `render` does: the rest of the window drawn
        /// without the shown page's host, and the host over it, read from the
        /// engines' surfaces directly where they can be read, and drawn again
        /// only when its layers changed since the last frame; nil when there
        /// is no host to draw.
        private static func composite(
            window: NSWindow, area: CGRect, columns: Int, rows: Int, sampler: inout BrowserMacHarnessLayerSampler,
            host cache: inout HostPixels
        ) -> [UInt8]? {
            guard let frameView = window.contentView?.superview, let root = frameView.layer,
                let host = shownHost(in: frameView), let hostLayer = host.layer
            else { return nil }
            // Hidden and shown again before the run loop commits, so the
            // window server never sees the change.
            let wasHidden = hostLayer.isHidden
            hostLayer.isHidden = true
            var pixels = render(window: window, area: area, columns: columns, rows: rows)
            hostLayer.isHidden = wasHidden
            var reach = 1.0
            var ancestor = hostLayer.superlayer
            while let current = ancestor, current !== root.superlayer {
                if current.isHidden { reach = 0 }
                reach *= Double(current.opacity)
                ancestor = current.superlayer
            }
            guard reach > 0 else { return pixels }
            let signature = BrowserMacHarnessLayerSampler.signature(of: hostLayer)
            if cache.signature != signature || cache.pixels.count != pixels.count {
                cache.signature = signature
                if let read = read(hostLayer, root: root, area: area, columns: columns, rows: rows, sampler: &sampler) {
                    cache.pixels = read
                    cache.reads += 1
                } else {
                    cache.pixels = draw(hostLayer, root: root, area: area, columns: columns, rows: rows)
                    cache.draws += 1
                }
            }
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Double(cache.pixels[index + 3]) / 255 * reach
                for channel in 0..<4 {
                    let top = Double(cache.pixels[index + channel]) / 255 * reach
                    let below = Double(pixels[index + channel]) / 255
                    pixels[index + channel] = UInt8(max(0, min(255, ((top + below * (1 - alpha)) * 255).rounded())))
                }
            }
            return pixels
        }

        /// The host's pixels read from its layers' surfaces, top row first,
        /// premultiplied; nil when some layer cannot be read.
        private static func read(
            _ hostLayer: CALayer, root: CALayer, area: CGRect, columns: Int, rows: Int,
            sampler: inout BrowserMacHarnessLayerSampler
        ) -> [UInt8]? {
            var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
            for row in 0..<rows {
                for column in 0..<columns {
                    let point = CGPoint(
                        x: area.minX + (Double(column) + 0.5) * area.width / Double(columns),
                        y: area.maxY - (Double(row) + 0.5) * area.height / Double(rows))
                    let sample = sampler.sample(hostLayer, at: hostLayer.convert(point, from: root))
                    guard sample.isComplete else { return nil }
                    let index = (row * columns + column) * 4
                    for channel in 0..<4 {
                        pixels[index + channel] = UInt8(max(0, min(255, (sample.color[channel] * 255).rounded())))
                    }
                }
            }
            return pixels
        }

        /// The host's pixels drawn from its layers alone, as `render` draws
        /// the window.
        private static func draw(_ hostLayer: CALayer, root: CALayer, area: CGRect, columns: Int, rows: Int)
            -> [UInt8]
        {
            var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
            let local = hostLayer.convert(area, from: root)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return pixels }
            pixels.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                        bytesPerRow: columns * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.interpolationQuality = .low
                if hostLayer.isGeometryFlipped {
                    context.translateBy(x: 0, y: CGFloat(rows))
                    context.scaleBy(x: CGFloat(columns) / local.width, y: -CGFloat(rows) / local.height)
                } else {
                    context.scaleBy(x: CGFloat(columns) / local.width, y: CGFloat(rows) / local.height)
                }
                context.translateBy(x: -local.minX, y: -local.minY)
                hostLayer.render(in: context)
            }
            return pixels
        }

        /// What the shown page was doing at a frame: its identity, commits,
        /// finished loads, whether it loads, and its view's class.
        private func frameState() -> String {
            guard let context = try? context() else { return "-" }
            guard let page = context.pages.activePage else {
                return "nopage tab=\(context.browser.shownTab?.id.uuidString.prefix(6) ?? "-")"
            }
            return
                "\(page.corePage.id.uuidString.prefix(6)) c\(page.committedNavigationCount) "
                + "d\(page.completedNavigationCount) \(page.live.isLoading ? "L" : "-") "
                + "\(page.nativeView.superview is BrowserWebHostView ? "on" : "off")"
        }

        /// WebKit stops drawing the pages of a window that is off the screens
        /// and treats them as hidden; the sampled window's pages draw as a
        /// shown window's do.
        func keepPagesDrawing(in window: NSWindow) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
            var changed = false
            for webView in Self.allWebViews(in: window.contentView?.superview ?? NSView())
            where webView.responds(to: selector) && !Self.drawingWebViews.contains(webView) {
                unsafeBitCast(webView.method(for: selector), to: Setter.self)(webView, selector, false)
                Self.drawingWebViews.add(webView)
                changed = true
            }
            // A page that already thought itself hidden looks again only when
            // its window's occlusion changes.
            if changed {
                NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
        }

        private static let drawingWebViews = NSHashTable<WKWebView>.weakObjects()

        private static func allWebViews(in view: NSView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(allWebViews(in:))
        }

        private static func javaScriptString(_ text: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
            return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
        }

        /// Every frame side by side, ten to a row.
        private static func contactSheet(_ frames: [SampledFrame], columns: Int, rows: Int) -> Data? {
            guard !frames.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            let perRow = 10
            let gap = 2
            let sheetRows = (frames.count + perRow - 1) / perRow
            let width = perRow * (columns + gap)
            let height = sheetRows * (rows + gap)
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (index, frame) in frames.enumerated() {
                var bytes = frame.pixels
                let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
                    CGContext(
                        data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                        bytesPerRow: columns * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
                }
                guard let image else { continue }
                let x = (index % perRow) * (columns + gap)
                let y = height - (index / perRow + 1) * (rows + gap)
                context.draw(image, in: CGRect(x: x, y: y, width: columns, height: rows))
            }
            guard let sheet = context.makeImage() else { return nil }
            return NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:])
        }

        // MARK: - Actions - Layers

        /// The shown page's layers under its host, for finding what draws the
        /// page: each layer's class, frame, opacity, background and contents.
        func pageLayers(depth: Int) throws -> [String: Any] {
            let window = try targetWindow()
            guard let frameView = window.contentView?.superview, let host = Self.shownHost(in: frameView),
                let layer = host.layer
            else { throw Failure(description: "No page is shown") }
            var lines: [String] = []
            func describe(_ layer: CALayer, _ level: Int) {
                guard lines.count < 400 else { return }
                var contents = "-"
                if let value = layer.contents {
                    let type = CFGetTypeID(value as CFTypeRef)
                    if type == IOSurfaceGetTypeID() {
                        let surface = unsafeBitCast(value as AnyObject, to: IOSurfaceRef.self)
                        let format = IOSurfaceGetPixelFormat(surface)
                        let code =
                            String(
                                bytes: [24, 16, 8, 0].map { UInt8((format >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
                        contents =
                            "surface \(IOSurfaceGetWidth(surface))x\(IOSurfaceGetHeight(surface)) \(code)"
                    } else {
                        contents = String(describing: Swift.type(of: value))
                    }
                }
                let background = layer.backgroundColor.map { color in
                    (color.components ?? []).map { String(format: "%.2f", $0) }.joined(separator: ",")
                }
                lines.append(
                    String(repeating: " ", count: level) + "\(type(of: layer)) \(layer.frame.integral) "
                        + "o\(layer.opacity) \(layer.isHidden ? "hidden " : "")bg[\(background ?? "-")] \(contents)"
                        + " subs\(layer.sublayers?.count ?? 0)")
                guard level < depth else { return }
                for sublayer in layer.sublayers ?? [] { describe(sublayer, level + 1) }
            }
            describe(layer, 0)
            return ["layers": lines]
        }
    }

#endif
