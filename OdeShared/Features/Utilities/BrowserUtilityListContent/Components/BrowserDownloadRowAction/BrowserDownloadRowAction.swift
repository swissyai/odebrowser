import Foundation
import SwiftUI

struct BrowserDownloadRowAction: View {
    let item: DownloadState
    let destinations: [BrowserUtilityDownloadDestination]
    /// A finished file that has since been moved or deleted offers only to
    /// leave the list.
    var isFileMissing = false
    /// The shell can move a finished file to the Trash.
    var offersMoveToTrash = false
    let perform: (BrowserUtilityDownloadAction) -> Void

    /// Every trailing control's glyph: one size and weight, in the secondary
    /// role, so Cancel and a finished file's menu read as one set.
    static let glyphFont = Font.system(size: 13, weight: .medium)

    /// Engine capabilities offer pause or recovery beside the phase's action.
    var body: some View {
        Group { controls }
            .font(Self.glyphFont)
            .foregroundStyle(SpaceRoleStyle.secondaryText)
    }

    @ViewBuilder
    private var controls: some View {
        if item.canPause {
            actionButton(.pause) { perform(.pause(item.id)) }
        } else if item.canResume {
            actionButton(.resume) { perform(.resume(item.id)) }
        }
        let action = isFileMissing ? DownloadRowAction.remove : item.phase.primaryAction
        if let request = action.request(for: item.id) {
            actionButton(action) { perform(request) }
        } else {
            BrowserDownloadFinishedAction(
                itemID: item.id,
                action: action,
                destinations: destinations,
                menu: BrowserDownloadMenu(
                    item: item, destinations: destinations, isFileMissing: isFileMissing,
                    offersMoveToTrash: offersMoveToTrash),
                perform: perform
            )
        }
    }

    private func actionButton(
        _ action: DownloadRowAction,
        perform: @escaping () -> Void
    ) -> some View {
        Button(
            action.title,
            systemImage: action.symbol,
            role: action.isDestructive ? .destructive : nil,
            action: perform
        )
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(
            width: BrowserUtilitySwitcherLayout.buttonSize,
            height: BrowserUtilitySwitcherLayout.buttonSize
        )
    }
}

#if DEBUG
    #Preview("Download actions") {
        VStack {
            BrowserDownloadRowAction(
                item: BrowserUtilityListPreviewFixture.activeDownload, destinations: [], perform: { _ in })
            BrowserDownloadRowAction(
                item: BrowserUtilityListPreviewFixture.failedDownload, destinations: [], perform: { _ in })
            BrowserDownloadRowAction(
                item: BrowserUtilityListPreviewFixture.finishedDownload, destinations: [], perform: { _ in })
        }.padding()
    }
#endif
