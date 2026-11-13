import Foundation

extension BrowserTabPreviewSite {
    // MARK: - Static Variables

    /// Fetches the unread feed of the account the page shows, from the
    /// page's own site with the page's own session, and answers its status
    /// and text. A redirect, which leads to signing in, is not followed.
    static let gmailReader = """
        const account = (location.pathname.match(/^\\/mail\\/u\\/(\\d+)/) || [null, "0"])[1];
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 15000);
        try {
          const response = await fetch(`/mail/u/${account}/feed/atom`, {
            credentials: "same-origin", cache: "no-store", redirect: "manual", signal: controller.signal,
          });
          if (!response.ok) return JSON.stringify({ status: response.status });
          const feed = await response.text();
          return JSON.stringify({ status: response.status, feed: feed.length <= 1048576 ? feed : null });
        } catch (_) {
          return null;
        } finally {
          clearTimeout(timer);
        }
        """

    /// Collects the events the calendar page shows: each one's id, the label
    /// it gives screen readers and the day of its column, with the account
    /// the page names. A page still drawing its grid answers nothing, so it
    /// is read again soon.
    static let calendarReader = """
        const chips = Array.from(document.querySelectorAll("[data-eventid]"));
        if (!chips.length && !document.querySelector("[data-datekey]")) return null;
        const seen = new Set();
        const events = [];
        for (const chip of chips) {
          const id = (chip.getAttribute("data-eventid") || "").slice(0, 256);
          if (!id || seen.has(id)) continue;
          seen.add(id);
          const spoken = Array.from(chip.children).find((child) =>
            child.getAttribute("aria-hidden") !== "true" && (child.textContent || "").trim());
          const label = (chip.getAttribute("aria-label") || (spoken && spoken.textContent) || "").trim().slice(0, 512);
          const column = chip.closest("[data-datekey]");
          const day = column ? Number(column.getAttribute("data-datekey")) : null;
          events.push({ id, label, day: Number.isInteger(day) ? day : null });
          if (events.length >= 200) break;
        }
        const named = Array.from(document.querySelectorAll("[aria-label*='@']"), (element) => element.getAttribute("aria-label"));
        const address = named.map((text) => (text.match(/[\\w.+-]+@[\\w-]+(?:\\.[\\w-]+)+/) || [])[0]).find(Boolean);
        return JSON.stringify({ account: address || null, events });
        """
}
