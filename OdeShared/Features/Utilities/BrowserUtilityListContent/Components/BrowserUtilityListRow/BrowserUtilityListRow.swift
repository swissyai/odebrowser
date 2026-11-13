import SwiftUI

struct BrowserUtilityListRow: View {
    // MARK: - Variables

    let item: BrowserUtilityListItem
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions

    @Environment(\.browserFavicons) private var favicons

    var body: some View {
        // List can gather row identities without resolving every row's branch.
        VStack(alignment: .leading, spacing: 0) {
            switch item {
            case .archive(let archived):
                Button {
                    actions.restoreArchivedTab(archived.tab.id, assignment)
                } label: {
                    BrowserUtilityListRowLabel(
                        title: archived.tab.shownTitle,
                        subtitle: archiveSubtitle(archived),
                        // The reason's symbol tells the reasons apart; the
                        // text keeps the secondary role's contrast.
                        subtitleStyle: AnyShapeStyle(SpaceRoleStyle.secondaryText)
                    ) {
                        TabFaviconView(
                            subject: BrowserTabFaviconSubject(
                                tab: archived.tab, image: favicons?.icon(of: archived.tab.id)),
                            profileID: assignment.profileID
                        )
                    } trailing: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(SpaceRoleStyle.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore \(archived.tab.shownTitle)")
                .accessibilityIdentifier(
                    BrowserTabAccessibilityID.archivedRow(archived.tab.id)
                )
                .contextMenu { archiveActions(archived) }
                .accessibilityActions { archiveActions(archived) }

            case .history(let entry):
                Button {
                    actions.openHistoryEntry(entry, assignment)
                } label: {
                    BrowserUtilityListRowLabel(
                        title: entry.title,
                        subtitle: historySubtitle(entry)
                    ) {
                        Image(systemName: "globe")
                    } trailing: {
                        Image(systemName: "arrow.up.forward")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(entry.title)")
                .accessibilityIdentifier(
                    BrowserUtilityAccessibilityID.historyRow(entry.url)
                )
                .contextMenu { historyActions(entry) }
                .accessibilityActions { historyActions(entry) }

            case .download(let download):
                BrowserUtilityDownloadRow(
                    download: download,
                    assignment: assignment,
                    actions: actions
                )
            }
        }
        .odeHoverSurface(
            cornerRadius: BrowserSidebarMetrics.layerCornerRadius()
        )
    }

    // MARK: - Actions - Menus

    @ViewBuilder
    private func archiveActions(_ archived: ArchivedTabState) -> some View {
        Button(String(localized: "Restore"), systemImage: "arrow.uturn.backward") {
            actions.restoreArchivedTab(archived.tab.id, assignment)
        }
        if let keep = actions.keepArchivedTab {
            Button(String(localized: "Pin"), systemImage: "pin") { keep(archived.tab.id, .pinned, assignment) }
            Button(String(localized: "Save"), systemImage: "bookmark") { keep(archived.tab.id, .saved, assignment) }
        }
    }

    @ViewBuilder
    private func historyActions(_ entry: HistoryPlace) -> some View {
        Button(String(localized: "Open"), systemImage: "arrow.up.forward") {
            actions.openHistoryEntry(entry, assignment)
        }
        if let keep = actions.keepHistoryEntry {
            Button(String(localized: "Pin"), systemImage: "pin") { keep(entry, .pinned, assignment) }
            Button(String(localized: "Save"), systemImage: "bookmark") { keep(entry, .saved, assignment) }
        }
        if let remove = actions.removeHistoryEntry {
            Divider()
            Button(String(localized: "Remove from History"), systemImage: "trash", role: .destructive) {
                remove(entry, assignment)
            }
        }
        if let removeSite = actions.removeHistorySite, URL(string: entry.url)?.host() != nil {
            Button(String(localized: "Remove All from This Site"), systemImage: "trash", role: .destructive) {
                removeSite(entry, assignment)
            }
        }
    }

    // MARK: - Actions - Presentation

    private func archiveSubtitle(_ archived: ArchivedTabState) -> Text {
        let icon = Image(systemName: archived.reason.symbol)
        let status = Text(archived.reason.title)
        if let host = archived.tab.url.flatMap(URL.init(string:))?.host() {
            return Text("\(icon) \(status) · \(host)")
        }
        return Text("\(icon) \(status)")
    }

    private func historySubtitle(_ entry: HistoryPlace) -> Text {
        let host = URL(string: entry.url)?.host() ?? entry.url
        guard entry.visitCount > 1 else { return Text(host) }
        return Text(
            BrowserUtilityPresentation.historyVisits(
                host: host,
                count: entry.visitCount
            )
        )
    }

}

private struct BrowserUtilityDownloadRow: View {
    let download: DownloadState
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions

    @Environment(\.browserFavicons) private var favicons

    var body: some View {
        HStack(spacing: 0) {
            // Every row is named by its file; what picking it does is the hint.
            if let primaryDestination {
                Button {
                    perform(.open(download.id, primaryDestination))
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .browserDownloadFileDrag(download)
                .accessibilityLabel(Text(verbatim: download.filename))
                .accessibilityValue(Text(verbatim: accessibilitySummary))
                .accessibilityHint(Text(primaryDestination.title))
                .accessibilityActions { menuItems }
            } else {
                label
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: download.filename))
                    .accessibilityValue(Text(verbatim: accessibilitySummary))
                    .accessibilityActions { menuItems }
            }

            BrowserDownloadRowAction(
                item: download,
                destinations: actions.downloadDestinations,
                isFileMissing: isFileMissing,
                offersMoveToTrash: actions.offersMoveToTrash,
                perform: perform
            )
        }
        .contextMenu { menuItems }
        .modifier(BrowserPlatformDownloadRowInteractions(download: download))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: download.filename))
        .accessibilityIdentifier(
            BrowserUtilityAccessibilityID.downloadRow(download.id)
        )
    }

    private var label: some View {
        BrowserDownloadRowLabel(download: download, isFileMissing: isFileMissing)
    }

    /// A finished file that is gone has nowhere to go.
    private var primaryDestination: BrowserUtilityDownloadDestination? {
        guard !isFileMissing else { return nil }
        return BrowserUtilityDownloadDestination.primary(
            for: download.phase,
            among: actions.downloadDestinations
        )
    }

    private var isFileMissing: Bool {
        download.isSavedFileMissing()
    }

    private var menuItems: some View {
        BrowserDownloadMenuItems(menu: menu, itemID: download.id, perform: perform)
    }

    private var menu: BrowserDownloadMenu {
        BrowserDownloadMenu(
            item: download, destinations: actions.downloadDestinations, isFileMissing: isFileMissing,
            offersMoveToTrash: actions.offersMoveToTrash)
    }

    private func perform(_ action: BrowserUtilityDownloadAction) {
        actions.performDownloadAction(action, assignment)
    }

    private var accessibilitySummary: String {
        let presentation = BrowserDownloadRowPresentation.resolve(item: download, fileIsMissing: isFileMissing)
        var components = [presentation.statusText.resolvedForSearch()]
        if presentation.showsTransferMetrics {
            components.append(accessibilityTransferMetrics(presentation))
        }
        if let bytesPerSecond = presentation.bytesPerSecond {
            let rate = Int64(bytesPerSecond.rounded()).formatted(
                .byteCount(style: .file)
            )
            components.append(String(localized: "\(rate) per second"))
        }
        if let estimatedTimeRemaining = presentation.estimatedTimeRemaining {
            components.append(
                String(
                    localized: "\(etaLabel(estimatedTimeRemaining)) remaining"
                )
            )
        }
        return components.joined(separator: ", ")
    }

    private func accessibilityTransferMetrics(
        _ presentation: BrowserDownloadRowPresentation
    ) -> String {
        if presentation.isComplete {
            return presentation.completedSize.formatted(.byteCount(style: .file))
        }
        let received = presentation.bytesReceived.formatted(
            .byteCount(style: .file)
        )
        guard let totalBytes = presentation.totalBytes else {
            return String(localized: "\(received) downloaded")
        }
        let total = totalBytes.formatted(.byteCount(style: .file))
        let progress = presentation.progress.formatted(
            .percent.precision(.fractionLength(0))
        )
        return String(
            localized: "\(received) of \(total), \(progress)"
        )
    }

    private func etaLabel(_ seconds: TimeInterval) -> String {
        BrowserDownloadRowPresentation.timeRemaining(seconds)
    }

}

private struct BrowserDownloadRowLabel: View {
    let download: DownloadState
    let isFileMissing: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: BrowserDownloadRowPresentation.iconSpacing) {
            BrowserDownloadStatusIcon(item: download)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(SpaceRoleStyle.secondaryText)
                .frame(width: BrowserDownloadRowPresentation.iconSide, height: BrowserDownloadRowPresentation.iconSide)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(download.filename)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                details
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, OdeSpacing.extraSmall)
        .padding(.vertical, OdeSpacing.small)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
    }

    @ViewBuilder
    private var details: some View {
        let presentation = BrowserDownloadRowPresentation.resolve(item: download, fileIsMissing: isFileMissing)
        switch presentation.layout(
            availableWidth: availableWidth,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        ) {
        case .singleLine:
            primaryLine(presentation)
        case .inline:
            HStack(spacing: 6) {
                primaryLine(presentation)
                Text("·").foregroundStyle(.tertiary)
                secondaryLine(presentation)
            }
            .lineLimit(1)
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                primaryLine(presentation)
                    .lineLimit(1)
                // A rate and a time left stay on one line; why a download
                // stopped wraps until it is said in full.
                secondaryLine(presentation)
                    .lineLimit(presentation.statusNeedsAttention ? nil : 1)
            }
        }
    }

    private func primaryLine(
        _ presentation: BrowserDownloadRowPresentation
    ) -> Text {
        guard presentation.showsTransferMetrics else {
            return styledStatus(presentation)
        }
        if presentation.isComplete {
            return Text("\(presentation.completedSize, format: .byteCount(style: .file))")
                .foregroundStyle(SpaceRoleStyle.secondaryText)
        }
        guard let totalBytes = presentation.totalBytes else {
            return Text(
                "\(presentation.bytesReceived, format: .byteCount(style: .file)) downloaded"
            )
            .foregroundStyle(SpaceRoleStyle.secondaryText)
        }
        return Text(
            "\(presentation.bytesReceived, format: .byteCount(style: .file)) of \(totalBytes, format: .byteCount(style: .file)) · \(presentation.progress, format: .percent.precision(.fractionLength(0)))"
        )
        .foregroundStyle(SpaceRoleStyle.secondaryText)
    }

    private func secondaryLine(
        _ presentation: BrowserDownloadRowPresentation
    ) -> Text {
        if let bytesPerSecond = presentation.bytesPerSecond {
            if let estimatedTimeRemaining = presentation.estimatedTimeRemaining {
                return Text(
                    "\(Int64(bytesPerSecond.rounded()), format: .byteCount(style: .file))/s · \(etaLabel(estimatedTimeRemaining)) remaining"
                )
                .foregroundStyle(SpaceRoleStyle.secondaryText)
            }
            return Text(
                "\(Int64(bytesPerSecond.rounded()), format: .byteCount(style: .file))/s"
            )
            .foregroundStyle(SpaceRoleStyle.secondaryText)
        }
        if let estimatedTimeRemaining = presentation.estimatedTimeRemaining {
            return Text(
                "\(etaLabel(estimatedTimeRemaining)) remaining"
            )
            .foregroundStyle(SpaceRoleStyle.secondaryText)
        }
        return styledStatus(presentation)
    }

    private func styledStatus(
        _ presentation: BrowserDownloadRowPresentation
    ) -> Text {
        if presentation.statusNeedsAttention {
            return presentation.statusText.view.foregroundStyle(SpaceRoleStyle.dangerText)
        }
        return presentation.statusText.view.foregroundStyle(SpaceRoleStyle.secondaryText)
    }

    private func etaLabel(_ seconds: TimeInterval) -> String {
        BrowserDownloadRowPresentation.timeRemaining(seconds)
    }
}
