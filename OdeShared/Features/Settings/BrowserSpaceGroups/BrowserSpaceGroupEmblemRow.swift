import SwiftUI
import UniformTypeIdentifiers

/// The Spaces of the group a Settings page edits, as a row of emblems between
/// the page's header and its tabs. Choosing an emblem edits that Space, + starts
/// another Sub-Space, and each emblem's menu moves it within the group, moves
/// it to another group, separates it or deletes it. A Space on its own shows
/// its one emblem and +, which is how its first Sub-Space starts, so the row
/// never comes or goes.
///
/// On the Mac an emblem also drags: onto another emblem of the row to move it
/// there, or onto Settings' list of Spaces to move it to another group or
/// bring it out on its own, which asks first.
struct BrowserSpaceGroupEmblemRow: View {
    // MARK: - Variables

    let browser: BrowserStore
    /// The Space the page edits.
    let space: SpaceModel
    var style: OdeSpaceIconPickerStyle = .compact
    var metrics: BrowserSpacePickerMetrics = .pointer
    /// The Space being dragged in Settings, which this row's emblems take.
    @Binding var draggedSpaceID: UUID?
    let select: (UUID) -> Void
    let addSubSpace: (UUID) -> Void
    let requestGroupChange: (BrowserSpaceGroupChange) -> Void
    let requestDeletion: (BrowserSpaceDeletionRequest) -> Void

    @State private var dropTargetID: UUID?

    var body: some View {
        let members = browser.groupMembers(of: space)
        HStack(spacing: OdeSpacing.small) {
            HStack(spacing: 0) {
                ForEach(members) { member in
                    emblem(member)
                }
            }
            .padding(style.trackPadding)
            .background {
                OdeSpaceIconPickerShape(style: style).fill(.primary.opacity(style.trackFillOpacity))
            }
            .overlay {
                OdeSpaceIconPickerShape(style: style)
                    .strokeBorder(.primary.opacity(style.trackBorderOpacity), lineWidth: OdeLayout.hairline / 2)
            }
            if !browser.isPrivateBrowsing, let last = members.last {
                Button("New Sub-Space", systemImage: "plus") { addSubSpace(last.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle(controlSize: CGSize(width: style.height, height: style.height)))
                    .help("New Sub-Space")
                    .accessibilityIdentifier("space-group-add-sub-space")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sub-Spaces")
        .accessibilityIdentifier("space-group-crests")
    }

    // MARK: - Emblems

    private func emblem(_ member: SpaceModel) -> some View {
        let isSelected = member.id == space.id
        let tint = member.identity.branding.primaryColor.color
        let isDropTarget = dropTargetID == member.id
        return Button {
            select(member.id)
        } label: {
            BrowserSpacePickerIcon(space: member.identity, metrics: metrics)
                .frame(width: style.minimumSegmentWidth, height: style.segmentHeight)
                .contentShape(.rect)
                .background {
                    if isSelected || isDropTarget {
                        OdeSpaceIconPickerShape(style: style)
                            .fill(
                                tint.opacity(isSelected ? style.selectionFillOpacity : style.selectionFillOpacity / 2)
                            )
                            .overlay {
                                OdeSpaceIconPickerShape(style: style).strokeBorder(
                                    tint, lineWidth: OdeLayout.hairline)
                            }
                    }
                }
        }
        .buttonStyle(.plain)
        .help(member.settings.name)
        .accessibilityLabel(Text(verbatim: member.settings.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("space-group-crest-\(member.id)")
        .contextMenu { menu(member).odeMenuActionLabelStyle() }
        #if os(macOS)
            .onDrag {
                draggedSpaceID = member.id
                return NSItemProvider(object: member.id.uuidString as NSString)
            }
            .onDrop(
                of: [.plainText],
                delegate: EmblemDrop(
                    target: member, browser: browser, draggedSpaceID: $draggedSpaceID, dropTargetID: $dropTargetID,
                    requestGroupChange: requestGroupChange))
        #endif
    }

    @ViewBuilder
    private func menu(_ member: SpaceModel) -> some View {
        // The primary leads its group; a Sub-Space moves among the others.
        if browser.isSubSpace(member) {
            let order = BrowserSpaceOrderActions(browser: browser, spaceID: member.id)
            Button("Move Left", systemImage: "arrow.left", action: order.moveUp).disabled(!order.canMoveUp)
            Button("Move Right", systemImage: "arrow.right", action: order.moveDown).disabled(!order.canMoveDown)
            Divider()
        }
        BrowserSpaceGroupMenuItems(
            browser: browser, space: member, requestGroupChange: requestGroupChange, addSubSpace: addSubSpace)
        Divider()
        BrowserSpaceDeletionMenuItems(browser: browser, space: member, requestDeletion: requestDeletion)
    }
}

#if os(macOS)
    /// An emblem taking a dragged Space: one of its own group moves to where the
    /// emblem stands, and one from elsewhere asks to join the group.
    private struct EmblemDrop: DropDelegate {
        let target: SpaceModel
        let browser: BrowserStore
        @Binding var draggedSpaceID: UUID?
        @Binding var dropTargetID: UUID?
        let requestGroupChange: (BrowserSpaceGroupChange) -> Void

        private var dragged: SpaceModel? {
            draggedSpaceID.flatMap { browser.spaceModel($0) }.flatMap { $0.id == target.id ? nil : $0 }
        }

        /// Whether the drop moves the dragged Space within the target's group.
        private var movesWithinGroup: Bool {
            guard let dragged else { return false }
            return browser.primary(of: dragged) === browser.primary(of: target) && browser.isSubSpace(dragged)
                && browser.isSubSpace(target)
        }

        func validateDrop(info: DropInfo) -> Bool {
            guard let dragged else { return false }
            return movesWithinGroup || BrowserSpaceGroupChange.joining(dragged, into: target, in: browser) != nil
        }

        func dropEntered(info: DropInfo) {
            dropTargetID = target.id
        }

        func dropExited(info: DropInfo) {
            if dropTargetID == target.id { dropTargetID = nil }
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            defer {
                dropTargetID = nil
                draggedSpaceID = nil
            }
            guard let dragged else { return false }
            if movesWithinGroup {
                browser.move(dragged.id, to: target.id)
                return true
            }
            guard let join = BrowserSpaceGroupChange.joining(dragged, into: target, in: browser) else { return false }
            requestGroupChange(join)
            return true
        }
    }
#endif
