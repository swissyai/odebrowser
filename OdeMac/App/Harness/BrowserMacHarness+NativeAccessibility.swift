#if DEBUG || ODE_REVIEW_BUILD

    import AppKit

    extension BrowserMacHarness {
        // MARK: - Actions - Accessibility

        /// Native accessibility nodes and AppKit controls, with window-relative
        /// frames. Some SwiftUI hosts expose no semantic children offscreen;
        /// the view-tree fallback keeps native controls inspectable in that case.
        func nativeAccessibility(window name: String?) throws -> [String: Any] {
            let window = try window(named: name)
            guard let content = window.contentView else {
                throw Failure(description: "The window has no content")
            }
            var visited = Set<ObjectIdentifier>()
            var nodes: [[String: Any]] = []
            func visit(_ object: Any, depth: Int, isSecure: Bool = false) {
                guard depth < 80, nodes.count < 10_000,
                    let element = object as? any NSAccessibilityProtocol,
                    visited.insert(ObjectIdentifier(element)).inserted
                else { return }
                let frame = element.accessibilityFrame()
                var node: [String: Any] = [
                    "role": element.accessibilityRole()?.rawValue ?? "",
                    "label": element.accessibilityLabel() ?? "",
                    "title": element.accessibilityTitle() ?? "",
                    "identifier": element.accessibilityIdentifier() ?? "",
                    "depth": depth,
                    "x": frame.minX - window.frame.minX,
                    "y": frame.minY - window.frame.minY,
                    "width": frame.width, "height": frame.height,
                    "enabled": element.isAccessibilityEnabled(),
                ]
                let secure =
                    isSecure || element.accessibilitySubrole() == .secureTextField
                    || object is NSSecureTextField
                if !secure {
                    if let value = element.accessibilityValue() as? String {
                        node["value"] = value
                    } else if let value = element.accessibilityValue() as? NSNumber {
                        node["value"] = value
                    }
                }
                nodes.append(node)
                let children = element.accessibilityChildren() ?? []
                for child in children {
                    visit(child, depth: depth + 1, isSecure: secure)
                }
                if let view = object as? NSView {
                    for child in view.subviews {
                        visit(child, depth: depth + 1, isSecure: secure)
                    }
                }
            }
            visit(window, depth: 0)
            visit(content, depth: 0)
            return ["nodes": nodes, "window": window.title]
        }

        /// Scrolls the main native form without synthesizing pointer or key events.
        func scrollNativeContent(to y: Double, window name: String?) throws -> [String: Any] {
            let window = try window(named: name)
            guard let content = window.contentView else {
                throw Failure(description: "The window has no content")
            }
            func scrollViews(in view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
            }
            guard
                let scroll = scrollViews(in: content).filter({
                    !$0.isHiddenOrHasHiddenAncestor && $0.frame.width > content.bounds.width / 3
                        && ($0.documentView?.frame.height ?? 0) > $0.contentSize.height
                }).max(by: { $0.frame.width < $1.frame.width })
            else {
                throw Failure(description: "No main native form scrolls")
            }
            let limit = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentSize.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), limit)))
            scroll.reflectScrolledClipView(scroll.contentView)
            return ["y": scroll.contentView.bounds.minY, "limit": limit]
        }
    }

#endif
