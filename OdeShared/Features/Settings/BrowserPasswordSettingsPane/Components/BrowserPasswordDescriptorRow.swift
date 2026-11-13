import SwiftUI

/// One saved password, as settings shows it: who it is for, where it signs in, how
/// narrowly it is scoped, and whether it synchronizes.
///
/// The shells' two copies of this row differed in three ways that were all
/// accidental — the desktop had a tooltip, touch had a wider hit target, and only the
/// desktop showed a row mid-delete. The tooltip and the hit target are platform
/// truths that `OdeControls` already resolves per platform; the progress state was
/// simply missing on touch and is here now.
struct BrowserPasswordDescriptorRow: View {
    let descriptor: CredentialDescriptor
    let space: BrowserSpaceIdentity?
    var isDeleting = false
    var isSelectionActive = false
    var isSelected = false
    let showDetails: () -> Void
    let requestDeletion: () -> Void
    var toggleSelection: () -> Void = {}

    var body: some View {
        HStack(spacing: OdeSpacing.small) {
            Button(action: primaryAction) {
                HStack(spacing: OdeSpacing.medium) {
                    leadingIcon

                    VStack(
                        alignment: .leading,
                        spacing: OdeFormRowMetrics.titleSpacing
                    ) {
                        Text(primaryLabel)
                            .font(OdeTypography.controlTitle)
                            .lineLimit(1)
                        Text(secondaryLabel)
                            .font(OdeTypography.metadata)
                            .foregroundStyle(OdeColor.textSecondary)
                            .lineLimit(1)

                        if let scopeLabel = descriptor.scope.settingsLabel {
                            Text(scopeLabel)
                                .font(OdeTypography.compactMetadata)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: OdeSpacing.small)

                    statusIcons

                    if !isSelectionActive && !isDeleting {
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .disabled(isDeleting)
            .accessibilityHint(
                isSelectionActive
                    ? "Adds or removes this password from the selection."
                    : "Authenticates before showing the saved password."
            )

            if isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else if !isSelectionActive {
                Menu("Password Actions", systemImage: "ellipsis.circle") {
                    Group {
                        Button("View Password", systemImage: "eye", action: showDetails)
                        Divider()
                        Button(
                            "Delete Password",
                            systemImage: "trash",
                            role: .destructive,
                            action: requestDeletion
                        )
                    }
                    .odeMenuActionLabelStyle()
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(minHeight: OdeFormRowMetrics.minimumHeight)
        .accessibilityElement(children: .contain)
        .contextMenu {
            if !isSelectionActive {
                Group {
                    Button("View Password", systemImage: "eye", action: showDetails)
                    Button(
                        "Delete Password",
                        systemImage: "trash",
                        role: .destructive,
                        action: requestDeletion
                    )
                }
                .odeMenuActionLabelStyle()
            }
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if isSelectionActive {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    isSelected
                        ? (space?.accent.tint.color ?? OdeBrandTheme.accent)
                        : .secondary
                )
                .accessibilityHidden(true)
        } else {
            Image(systemName: "key.fill")
                .foregroundStyle(space?.accent.tint.color ?? OdeBrandTheme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var statusIcons: some View {
        if descriptor.isSynchronizable {
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
                .help("Synchronized through Ode’s iCloud Keychain item")
                .accessibilityLabel("iCloud synchronization on")
        }

        if !descriptor.origin.isSecure {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(OdeColor.warning)
                .help(
                    "Imported from an insecure HTTP site. Ode keeps it available for manual access but does not autofill it on insecure connections."
                )
                .accessibilityLabel("Manual access only for insecure HTTP site")
        }
    }

    private var primaryLabel: String {
        descriptor.displayName ?? descriptor.origin.host
    }

    private var secondaryLabel: String {
        let account =
            descriptor.username.isEmpty
            ? String(localized: "No username")
            : descriptor.username
        return descriptor.displayName == nil
            ? "\(account) · \(descriptor.origin.description)"
            : "\(account) · \(descriptor.origin.host)"
    }

    private func primaryAction() {
        if isSelectionActive {
            toggleSelection()
        } else {
            showDetails()
        }
    }
}

#if DEBUG
    #Preview("Saved account") {
        BrowserPasswordDescriptorRow(
            descriptor: BrowserCredentialDetailPreviewFixture.descriptor,
            space: BrowserSpaceBrandingPreviewFixture.simpleSpace.identity, showDetails: {}, requestDeletion: {}
        )
        .padding().frame(width: 400)
    }
#endif
