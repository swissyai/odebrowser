import SwiftUI

/// Tells its window's preview card where a pinned or saved tab with a preview
/// is and when the pointer rests on it, and offers Show Preview to assistive
/// technologies. A shell without preview cards leaves the row or tile as it
/// is.
struct BrowserTabPreviewHoverSource: ViewModifier {
    // MARK: - Variables

    let assignment: BrowserTabRuntimeAssignment
    /// Whether the tab has a preview to show now.
    let hasPreview: Bool

    @Environment(BrowserTabPreviewHover.self) private var hover: BrowserTabPreviewHover?

    func body(content: Content) -> some View {
        content
            .background {
                if hasPreview, let hover {
                    Color.clear
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global)
                        } action: {
                            hover.place(assignment, at: $0)
                        }
                        .onDisappear { hover.place(assignment, at: nil) }
                }
            }
            .onHover { isOver in
                guard let hover, hasPreview || !isOver else { return }
                hover.pointer(isOver: isOver, on: assignment)
            }
            .accessibilityAction(named: Text("Show Preview")) {
                guard hasPreview else { return }
                hover?.show(assignment)
            }
    }
}
