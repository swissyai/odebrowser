import SwiftUI

struct BrowserSourceImportSectionHeader: View {
    let title: LocalizedStringResource
    let tabs: [TabStateModel]
    let includedTabIDs: Set<UUID>
    let setIncluded: (Set<UUID>, Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(includesAll ? "Leave all" : "Include all") {
                setIncluded(tabIDs, !includesAll)
            }
            .buttonStyle(.borderless)
            .odeControlPointer()
            .font(.caption2)
        }
        .frame(minHeight: 24)
    }

    private var tabIDs: Set<UUID> { Set(tabs.map(\.id)) }
    private var includesAll: Bool { tabIDs.isSubset(of: includedTabIDs) }
}
