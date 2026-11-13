import SwiftUI

/// A pinned or saved tab's preview, shown beside the tab while the pointer
/// rests on it: the site and account, then the newest unread messages, each
/// with its sender, or the next events, each with its time. Choosing a row
/// opens it in the tab; choosing the header shows the tab.
struct BrowserTabPreviewCard: View {
    // MARK: - Static Variables

    static let width: CGFloat = 300
    /// The most messages or events the card lists.
    static let maximumRows = 5

    // MARK: - Variables

    let preview: BrowserTabPreview
    let site: BrowserTabPreviewSite
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    /// Opens the item in the tab, or shows the tab for nil.
    let open: (BrowserTabPreview.Item?) -> Void

    @Environment(\.browserChromeAppearance) private var chromeAppearance

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(at: context.date)
        }
        .padding(OdeSpacing.small)
        .frame(width: Self.width, alignment: .leading)
        .clipShape(shape)
        // The Command Bar's own panel: a solid surface over a strong blur,
        // a hairline and a soft shadow, so the card reads the same over any
        // page in either appearance.
        .modifier(BrowserCommandPaletteShellMaterial(shape: shape))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text("\(Text(site.title)) preview", comment: "Accessibility label of a tab's preview card."))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: chromeAppearance.cornerScale.surface, style: .continuous)
    }

    private var rowCornerRadius: CGFloat { chromeAppearance.cornerScale.row }

    // MARK: - Actions - Layout

    private func content(at now: Date) -> some View {
        let items = Array(preview.current(at: now).prefix(Self.maximumRows))
        return VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
            header
            Divider()
                .padding(.horizontal, OdeSpacing.small)
                .padding(.vertical, OdeSpacing.extraExtraSmall)
            if preview.isSignedOut {
                message(Text("Signed out of \(Text(site.title))", comment: "A tab preview whose page is signed out."))
            } else if items.isEmpty {
                message(Text(site.emptyText))
            } else {
                ForEach(items) { item in
                    row(item, at: now)
                }
            }
            if now.timeIntervalSince(preview.readAt) > 2 * site.refreshInterval {
                Text(
                    "Updated \(preview.readAt.formatted(.relative(presentation: .named)))",
                    comment: "When a tab preview that is no longer current was read."
                )
                .font(OdeTypography.compactMetadata)
                .foregroundStyle(.panelDetail)
                .padding(.horizontal, OdeSpacing.small)
                .padding(.top, OdeSpacing.extraExtraSmall)
            }
        }
    }

    private var header: some View {
        Button {
            open(nil)
        } label: {
            HStack(spacing: OdeSpacing.small) {
                TabStateFaviconView(tab: tab, favicons: favicons, profileID: profileID, size: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(site.title)
                        .font(.subheadline.weight(.semibold))
                    if let account = preview.account {
                        Text(verbatim: account)
                            .font(OdeTypography.compactMetadata)
                            .foregroundStyle(.panelDetail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: OdeSpacing.small)
                if let unreadCount = preview.unreadCount, unreadCount > 0, !preview.isSignedOut {
                    Text("\(unreadCount) unread", comment: "Accessibility label of a tab's unread mail count.")
                        .font(OdeTypography.metadata)
                        .foregroundStyle(.panelDetail)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, OdeSpacing.small)
            .padding(.vertical, OdeSpacing.extraSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .odeHoverSurface(cornerRadius: rowCornerRadius)
        .help(Text("Show Tab"))
    }

    private func message(_ text: Text) -> some View {
        text
            .font(.subheadline)
            .foregroundStyle(.panelDetail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OdeSpacing.small)
            .padding(.vertical, OdeSpacing.small)
    }

    private func row(_ item: BrowserTabPreview.Item, at now: Date) -> some View {
        Button {
            open(item)
        } label: {
            Group {
                if let sender = item.sender {
                    messageRow(item, sender: sender, at: now)
                } else {
                    eventRow(item, at: now)
                }
            }
            .padding(.horizontal, OdeSpacing.small)
            .padding(.vertical, OdeSpacing.extraSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .odeHoverSurface(cornerRadius: rowCornerRadius)
    }

    private func messageRow(_ item: BrowserTabPreview.Item, sender: String, at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
                Text(verbatim: sender)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: OdeSpacing.small)
                if let date = item.date {
                    Text(verbatim: Self.receivedText(date, now: now))
                        .font(OdeTypography.compactMetadata)
                        .foregroundStyle(.panelDetail)
                        .monospacedDigit()
                }
            }
            Text(verbatim: item.title)
                .font(.subheadline)
                .foregroundStyle(.panelDetail)
                .lineLimit(1)
        }
    }

    private func eventRow(_ item: BrowserTabPreview.Item, at now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
            Text(verbatim: Self.timeText(item, now: now))
                .font(.subheadline)
                .foregroundStyle(.panelDetail)
                .monospacedDigit()
                .fixedSize()
            Text(verbatim: item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions - Dates

    /// When a message came: its time today, else its day.
    private static func receivedText(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// When an event runs: its times today, or its day and start on a later
    /// day, and All day for one that lasts the day.
    private static func timeText(_ item: BrowserTabPreview.Item, now: Date) -> String {
        guard let start = item.date else { return "" }
        let isToday = Calendar.current.isDate(start, inSameDayAs: now)
        let day = start.formatted(.dateTime.weekday(.abbreviated))
        if item.isAllDay {
            let allDay = String(localized: "All day", comment: "When a calendar event that lasts the day runs.")
            return isToday ? allDay : "\(day) \(allDay.lowercased())"
        }
        let time = start.formatted(date: .omitted, time: .shortened)
        guard isToday else { return "\(day) \(time)" }
        guard let end = item.endDate else { return time }
        return (start..<max(end, start)).formatted(.interval.hour().minute())
    }
}
