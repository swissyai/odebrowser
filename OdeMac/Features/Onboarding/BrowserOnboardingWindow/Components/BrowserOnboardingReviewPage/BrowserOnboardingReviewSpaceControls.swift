import SwiftUI

/// What a reviewed Space brings along, as one card: the Space itself and
/// where it goes, then its tabs, its saved passwords and its extensions, each
/// a row with a checkbox.
struct BrowserOnboardingReviewChecklist: View {
    let flow: BrowserOnboardingFlow
    let application: ImportSource?
    let review: BrowserImportSpaceReview
    let analysis: BrowserImportReviewAnalysis

    var body: some View {
        VStack(spacing: 0) {
            spaceRow
            Divider()
            tabsRow
            if application?.suppliesPasswords == true {
                Divider()
                passwordsRow
            } else if let application {
                Divider()
                passwordsStayNote(application)
            }
            if !review.extensions.isEmpty {
                Divider()
                extensionsRow
            }
        }
        .background(
            OdeBrandTheme.quietFill, in: .rect(cornerRadius: OdeRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OdeRadius.card, style: .continuous)
                .strokeBorder(OdeBrandTheme.line, lineWidth: OdeLayout.hairline)
        }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            if isOutOfRoom {
                Text("No room for another Space")
                    .font(OdeTypography.sans(11, weight: .medium))
                    .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What \(review.sourceSpace.settings.name) brings")
    }

    // MARK: - Rows

    private var spaceRow: some View {
        BrowserOnboardingReviewRow(
            isOn: spaceInclusion, canToggle: !isOutOfRoom, accessibilityLabel: "Bring this Space"
        ) {
            // The name takes its own line, where a long one wraps rather than
            // giving way to the menu; where the Space goes sits under it.
            VStack(alignment: .leading, spacing: 4) {
                Text(review.sourceSpace.settings.name)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(review.sourceSpace.settings.name)
                HStack(spacing: 6) {
                    Text("Into")
                        .font(OdeTypography.sans(12, weight: .medium))
                        .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.6))
                    BrowserOnboardingReviewDestinationMenu(
                        spaces: flow.destinationSpaces,
                        destination: destination,
                        destinationName: flow.destinationName(for: review.destination)
                    )
                    .disabled(!review.isIncluded)
                }
                if let groupLabel {
                    // Any Space of a group can still come in on its own.
                    HStack(spacing: 8) {
                        Text(groupLabel)
                            .font(OdeTypography.sans(11, weight: .medium))
                            .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.6))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            flow.separate(review.id)
                        } label: {
                            Text("Separate")
                                .font(OdeTypography.sans(12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                        }
                        .buttonStyle(
                            OdeChromeButtonStyle(
                                controlSize: nil, cornerRadius: OdeRadius.compact, showsRestingFill: true)
                        )
                        .accessibilityIdentifier("onboarding-review-separate")
                    }
                }
            }
            .padding(.vertical, groupLabel == nil ? 0 : 10)
            Spacer(minLength: 0)
        }
    }

    private var tabsRow: some View {
        BrowserOnboardingReviewRow(isOn: tabInclusion, accessibilityLabel: "Bring its tabs") {
            VStack(alignment: .leading, spacing: 1) {
                Text(BrowserOnboardingSummary.tabCount(review.includedTabIDs.count))
                if overflowCount > 0 {
                    Text(BrowserOnboardingSummary.overflowCount(overflowCount))
                        .font(OdeTypography.sans(11, weight: .medium))
                        .foregroundStyle(OdeBrandTheme.textSecondary)
                }
            }
        }
        .disabled(!review.isIncluded)
    }

    private var passwordsRow: some View {
        BrowserOnboardingReviewRow(
            isOn: passwordInclusion, accessibilityLabel: "Bring passwords for \(review.sourceSpace.settings.name)"
        ) {
            Text(flow.passwordCountLabel(for: review))
        }
        .disabled(!review.isIncluded || review.record.passwordCount == 0)
    }

    /// Where Ode reads no passwords from the browser, the card says they
    /// stay there rather than leaving them out without a word.
    private func passwordsStayNote(_ application: ImportSource) -> some View {
        Text("Passwords stay in \(flow.review?.title ?? application.title)")
            .font(OdeTypography.sans(13, weight: .medium))
            .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .accessibilityIdentifier("onboarding-review-passwords-stay")
    }

    private var extensionsRow: some View {
        BrowserOnboardingReviewRow(
            isOn: extensionInclusion, accessibilityLabel: "Install extensions for \(review.sourceSpace.settings.name)"
        ) {
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    BrowserOnboardingSummary.extensionCount(
                        included: review.includedExtensionIDs.count, total: review.extensions.count))
                Text(review.extensions.map(\.name).joined(separator: ", "))
                    .font(OdeTypography.sans(11, weight: .medium))
                    .foregroundStyle(OdeBrandTheme.textSecondary)
                    .lineLimit(1)
                    .help(review.extensions.map(\.name).joined(separator: ", "))
            }
        }
        .disabled(!review.isIncluded)
    }

    // MARK: - Choices

    /// The group a new Space comes in with: the Space it joins as a Sub-Space,
    /// the workspace's own or one the review brings, or the Sub-Spaces it
    /// leads. Nil for a Space that comes in alone or joins an existing Space.
    private var groupLabel: String? {
        guard review.comesInNew else { return nil }
        if let existing = review.existingGroupID {
            return flow.destinationSpaces.first { $0.id == existing }
                .map { String(localized: "Sub-Space of \($0.settings.name)") }
        }
        let group = flow.reviewGroup(of: review)
        guard let lead = group.first, group.count > 1 else { return nil }
        if lead.id != review.id { return String(localized: "Sub-Space of \(lead.sourceSpace.settings.name)") }
        return group.count == 2
            ? String(localized: "With a Sub-Space") : String(localized: "With \(group.count - 1) Sub-Spaces")
    }

    /// The Space would come in new, but Ode holds no more new Spaces.
    private var isOutOfRoom: Bool {
        !review.isIncluded && review.destination == .newSpace && (flow.review?.newSpaceCapacity ?? 1) == 0
    }

    /// The Space's pinned tabs that move to a saved folder.
    private var overflowCount: Int {
        analysis.overflowTabIDs.intersection(review.includedTabIDs).count
    }

    private var destination: Binding<BrowserImportDestination> {
        Binding(get: { review.destination }, set: { flow.setDestination($0, for: review.id) })
    }

    private var spaceInclusion: Binding<Bool> {
        Binding(get: { review.isIncluded }, set: { flow.setSpaceIncluded($0, in: review.id) })
    }

    /// Every tab the Space holds, on while any of them comes in.
    private var tabInclusion: Binding<Bool> {
        Binding(
            get: { !review.includedTabIDs.isEmpty },
            set: { flow.setIncluded(Set(review.sourceSpace.tabs.models.map(\.id)), $0, in: review.id) })
    }

    private var passwordInclusion: Binding<Bool> {
        Binding(
            get: { review.includesPasswords && review.record.passwordCount > 0 },
            set: { flow.setPasswordsIncluded($0, in: review.id) })
    }

    private var extensionInclusion: Binding<Bool> {
        Binding(get: { !review.includedExtensionIDs.isEmpty }, set: { flow.setExtensionsIncluded($0, in: review.id) })
    }
}

/// One row of the checklist: a checkbox and what it brings.
private struct BrowserOnboardingReviewRow<Content: View>: View {
    @Binding var isOn: Bool
    /// Whether the checkbox may change; the rest of the row stays usable.
    var canToggle = true
    let accessibilityLabel: LocalizedStringResource
    @ViewBuilder let content: Content
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!canToggle)
                .accessibilityLabel(Text(accessibilityLabel))
            HStack(spacing: 8) { content }
                .font(OdeTypography.sans(14, weight: .semibold))
                .foregroundStyle(OdeBrandTheme.textDisplay)
                .opacity(isEnabled ? 1 : 0.55)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

/// Where the Space goes: a new Space, or one Ode already has.
private struct BrowserOnboardingReviewDestinationMenu: View {
    /// The widest the menu grows; a long Space name truncates in it.
    static let maximumWidth: CGFloat = 160

    let spaces: [SpaceModel]
    @Binding var destination: BrowserImportDestination
    let destinationName: String

    var body: some View {
        Menu {
            Picker("Destination Space", selection: $destination) {
                Label("New Space", systemImage: "plus").tag(BrowserImportDestination.newSpace)
                ForEach(spaces) { space in
                    BrowserSpaceIdentityLabel(space: space).tag(BrowserImportDestination.existing(space.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .odeMenuActionLabelStyle()
        } label: {
            HStack(spacing: 6) {
                if let space = spaces.first(where: { destination.spaceID == $0.id }) {
                    BrowserSpaceIdentityLabel(space: space, iconSize: 16)
                } else {
                    Text("New Space")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(OdeTypography.sans(12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .frame(maxWidth: BrowserOnboardingReviewDestinationMenu.maximumWidth, minHeight: 28)
            .background(
                OdeBrandTheme.quietFill, in: .rect(cornerRadius: OdeRadius.compact, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OdeRadius.compact, style: .continuous)
                    .strokeBorder(OdeBrandTheme.line, lineWidth: OdeLayout.hairline)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help(destinationName)
        .accessibilityLabel("Where this Space goes")
        .accessibilityValue(destinationName)
    }
}
