import SwiftUI

/// The level ad blocking blocks at: Off, Balanced or Strict, each of which
/// sets the filter lists below to what it turns on. Once the person turns a
/// list against the level, the row says "Customized", and its reset restores
/// the level's lists. That word keeps its place while hidden, so the picker
/// never moves.
struct BrowserAdBlockingLevelSection: View {
    let core: OdeCore
    let errorDescription: String?

    var body: some View {
        let lists = core.state.filterLists
        Section {
            OdeSettingRow("Blocking", setting: restore(lists)) {
                HStack(spacing: OdeSettingRowMetrics.controlSpacing) {
                    Text("Customized")
                        .font(OdeTypography.metadata)
                        .foregroundStyle(OdeColor.textSecondary)
                        .opacity(lists.isCustomized ? 1 : 0)
                        .accessibilityHidden(true)
                    Picker("Blocking", selection: level) {
                        ForEach(ContentBlockingLevel.all, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityValue(
                        lists.isCustomized
                            ? Text("\(Text(lists.level.title)), customized") : Text(lists.level.title)
                    )
                    .accessibilityIdentifier("ad-blocking-level")
                }
            }
            if lists.level.blocksContent, let errorDescription {
                Label(errorDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(OdeColor.warning)
            }
        } footer: {
            Text(lists.level.summary)
        }
    }

    private var level: Binding<ContentBlockingLevel> {
        Binding {
            core.state.filterLists.level
        } set: { level in
            _ = try? core.send(SetContentBlockingLevel(level: level))
        }
    }

    /// Choosing the level in force again restores its lists.
    private func restore(_ lists: FilterLists) -> OdeResettableSetting {
        OdeResettableSetting(title: "Blocking", isDefault: !lists.isCustomized) {
            _ = try? core.send(SetContentBlockingLevel(level: lists.level))
        }
    }
}
