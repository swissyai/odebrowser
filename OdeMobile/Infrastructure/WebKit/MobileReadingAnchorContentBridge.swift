import WebKit

/// Keeps a page's reading position when the window changes width.
///
/// A wider or narrower viewport reflows the text above what the person is
/// reading, so the same scroll offset lands somewhere else: folding or
/// unfolding a phone, or turning it, would lose their place. The script notes
/// the block at the top of the visible page, and which part of it, as they
/// scroll; once a width change has laid out, it scrolls that same part of that
/// block back to the top. A page at its very top stays at its top.
@MainActor
enum MobileReadingAnchorContentBridge {
    // MARK: - Static Variables

    static let contentWorld = WKContentWorld.world(name: "Ode.ReadingAnchor")

    // MARK: - Actions - Installing

    static func install(in userContentController: WKUserContentController) {
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: contentWorld
            )
        )
    }

    // MARK: - Static Variables - Script

    private static let source = #"""
        (() => {
          if (globalThis.__odeReadingAnchorInstalled) return;
          globalThis.__odeReadingAnchorInstalled = true;

          // A little below the top edge, clear of a hairline header border.
          const probeY = 8;
          let anchor = null;
          let width = globalThis.innerWidth;
          let recordTimer = 0;
          let restoring = false;

          const isPinned = element => {
            for (let node = element; node && node !== document.documentElement; node = node.parentElement) {
              const position = getComputedStyle(node).position;
              if (position === 'fixed' || position === 'sticky') return true;
            }
            return false;
          };

          const blockAt = y => {
            for (const share of [0.5, 0.25, 0.75]) {
              let node = document.elementFromPoint(globalThis.innerWidth * share, y);
              if (!node || isPinned(node)) continue;
              while (node && node !== document.body && node !== document.documentElement) {
                if (getComputedStyle(node).display !== 'inline' && node.getBoundingClientRect().height > 0) return node;
                node = node.parentElement;
              }
            }
            return null;
          };

          const scrollRange = () =>
            Math.max(document.documentElement.scrollHeight - globalThis.innerHeight, 1);

          const record = () => {
            if (restoring) return;
            if (globalThis.scrollY <= 0) {
              anchor = null;
              return;
            }
            const element = blockAt(probeY);
            if (!element) {
              anchor = { share: globalThis.scrollY / scrollRange() };
              return;
            }
            const rect = element.getBoundingClientRect();
            anchor = { element, fraction: (probeY - rect.top) / Math.max(rect.height, 1) };
          };

          const settle = () =>
            requestAnimationFrame(() => {
              restoring = false;
              record();
            });

          const restore = () => {
            const kept = anchor;
            let target;
            if (kept && kept.element && kept.element.isConnected) {
              const rect = kept.element.getBoundingClientRect();
              target = globalThis.scrollY + rect.top + kept.fraction * rect.height - probeY;
            } else if (kept && kept.share !== undefined) {
              target = kept.share * scrollRange();
            }
            if (target !== undefined) globalThis.scrollTo(globalThis.scrollX, Math.max(0, target));
            settle();
          };

          // Noted once scrolling rests: a width change scrolls the page as it
          // starts, just before its resize event, and that scroll must not
          // replace the place being read.
          globalThis.addEventListener('scroll', () => {
            if (restoring) return;
            clearTimeout(recordTimer);
            recordTimer = setTimeout(record, 150);
          }, { passive: true });

          globalThis.addEventListener('resize', () => {
            if (globalThis.innerWidth === width) return;
            width = globalThis.innerWidth;
            clearTimeout(recordTimer);
            restoring = true;
            // Two frames: the first lays the new width out, the second sees it.
            requestAnimationFrame(() => requestAnimationFrame(restore));
          });

          record();
        })();
        """#
}
