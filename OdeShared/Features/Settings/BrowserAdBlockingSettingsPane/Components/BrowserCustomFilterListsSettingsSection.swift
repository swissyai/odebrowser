import SwiftUI

/// The filter lists the person subscribes to by address, each with its own
/// switch, which update on their own like the catalog's, and the field that
/// adds another.
struct BrowserCustomFilterListsSettingsSection: View {
    let core: OdeCore

    @State private var newListAddress = ""
    @State private var addError: String?

    var body: some View {
        Section {
            ForEach(core.state.filterLists.customLists, id: \.list.id) { state in
                row(state)
            }
            HStack(spacing: OdeSettingRowMetrics.controlSpacing) {
                TextField("Filter list address", text: $newListAddress, prompt: Text("https://example.com/list.txt"))
                    .labelsHidden()
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(addList)
                    .accessibilityIdentifier("ad-blocking-list-address")
                Button("Add List", action: addList)
                    .disabled(newListAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addError {
                Text(addError)
                    .font(OdeTypography.metadata)
                    .foregroundStyle(OdeColor.textSecondary)
            }
        } header: {
            Text("Your Lists")
        } footer: {
            Text("Lists update automatically.")
        }
    }

    private func row(_ state: CustomFilterListState) -> some View {
        HStack {
            Toggle(isOn: isOn(state.list.id)) {
                VStack(alignment: .leading, spacing: OdeFormRowMetrics.titleSpacing) {
                    Text(state.title)
                    Text(state.list.url)
                        .font(OdeTypography.metadata)
                        .foregroundStyle(OdeColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if state.list.isOn, state.isTooLarge {
                        note("Too large to use")
                    } else if state.list.isOn, state.isFailing {
                        note("Couldn’t update")
                    }
                }
            }
            Button {
                _ = try? core.send(RemoveCustomFilterList(id: state.list.id))
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(OdeChromeButtonStyle())
            .accessibilityLabel("Remove \(state.title)")
            .help("Remove \(state.title)")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(OdeTypography.metadata)
            .foregroundStyle(OdeColor.textSecondary)
    }

    private func isOn(_ id: UUID) -> Binding<Bool> {
        Binding {
            core.state.filterLists.customLists.first { $0.list.id == id }?.list.isOn ?? false
        } set: { isOn in
            _ = try? core.send(SetCustomFilterList(id: id, isOn: isOn))
        }
    }

    private func addList() {
        let address = newListAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        do {
            _ = try core.send(AddCustomFilterList(id: UUID(), url: address))
            newListAddress = ""
            addError = nil
        } catch {
            if case .customFilterListLimitReached(let limit) = error {
                addError = String(localized: "You can add up to \(limit.limit) lists.")
            } else {
                addError = String(localized: "Enter an https address.")
            }
        }
    }
}
