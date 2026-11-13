import SwiftUI

struct BrowserUtilityListSectionList: View {
    let sections: [BrowserUtilityListSection]
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions
    let dismissOnBlankSpace: (() -> Void)?
    var reachEnd: (() -> Void)? = nil

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        BrowserUtilityListRow(
                            item: item,
                            assignment: assignment,
                            actions: actions
                        )
                        .onAppear {
                            if item.id == lastItemID { reachEnd?() }
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: OdeSpacing.extraExtraSmall,
                                leading: OdeSpacing.small,
                                bottom: OdeSpacing.extraExtraSmall,
                                trailing: OdeSpacing.small
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Group {
                        if let site = section.site {
                            Text(verbatim: site)
                        } else {
                            Text(section.timeframe.title)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpaceRoleStyle.secondaryText)
                    .textCase(nil)
                }
                .listSectionSeparator(.hidden)
            }
            if let reachEnd {
                // In Site grouping, another page can add rows to an earlier
                // group without changing the last row's identity. Keep an
                // explicit route to the next page as well as scroll loading.
                Button(String(localized: "Show More History"), action: reachEnd)
                    .buttonStyle(.borderless)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {
                    dismissOnBlankSpace?()
                }
        }
        // Preserve native row-height estimates on macOS for long history lists.
        #if !os(macOS)
            .environment(\.defaultMinListRowHeight, 1)
        #endif
    }

    private var lastItemID: BrowserUtilityListItemID? { sections.last?.items.last?.id }

}
