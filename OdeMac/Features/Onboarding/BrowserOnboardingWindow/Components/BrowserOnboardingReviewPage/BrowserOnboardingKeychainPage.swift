import SwiftUI

/// Explains, before macOS asks, why importing a browser's passwords needs its
/// key from the Mac's keychain, what stays where, and what the system's
/// buttons mean; with a way to import without passwords instead.
struct BrowserOnboardingKeychainPage: View {
    let browserTitle: String
    /// Whether macOS refused the key the last time it asked.
    let wasRefused: Bool
    let isImporting: Bool
    let back: () -> Void
    let continueImport: () -> Void
    let importWithoutSecrets: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .center, spacing: 48) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Unlock selected data from \(browserTitle)")
                            .font(OdeTypography.display(BrowserOnboardingStageMetrics.headlineSize))
                            .foregroundStyle(OdeBrandTheme.textDisplay)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        paragraph(
                            "Ode needs \(browserTitle)'s Keychain key for the saved passwords you selected and, from Arc only, any selected sign-ins into new Spaces."
                        )
                        paragraph(
                            "Sign-in cookies stay in the destination's local browser profile. Imported passwords may sync with iCloud if that Space enables password sync."
                        )
                        paragraph(
                            "If macOS asks, use your Mac's login password. Allow grants access now; Always Allow can also grant future access. Deny leaves the key locked."
                        )
                        if wasRefused {
                            Label {
                                Text(
                                    "The Keychain key couldn't be read. Try again, change your choices, or import without passwords and sign-ins."
                                )
                                .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .font(OdeTypography.sans(13, weight: .medium))
                            .foregroundStyle(SpaceRoleStyle.dangerText)
                            .accessibilityIdentifier("onboarding-keychain-refused")
                        }
                    }
                    .frame(maxWidth: 440, alignment: .leading)

                    BrowserOnboardingKeychainDialogPicture(browserTitle: browserTitle)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, BrowserOnboardingStageMetrics.pageInset)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            BrowserOnboardingFooter(
                back: BrowserOnboardingBackAction(closes: false, action: back), isBackDisabled: isImporting
            ) {
                HStack(spacing: 18) {
                    Button("Import Without Passwords or Sign-ins", action: importWithoutSecrets)
                        .buttonStyle(.odeSecondary)
                        .fixedSize()
                        .disabled(isImporting)
                        .accessibilityIdentifier("onboarding-keychain-skip")
                    BrowserOnboardingContinueButton(
                        isImporting ? Text("Importing…") : Text("Continue"), action: continueImport
                    )
                    .disabled(isImporting)
                    .accessibilityIdentifier("onboarding-keychain-continue")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-keychain-page")
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(OdeTypography.sans(15, weight: .regular))
            .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A drawing of the dialog macOS shows next, with its parts named rather than
/// a picture of the system's own window.
private struct BrowserOnboardingKeychainDialogPicture: View {
    let browserTitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.7))
                Text(
                    "Ode wants to use your confidential information stored in “\(browserTitle) Safe Storage” in your keychain."
                )
                .font(OdeTypography.sans(12, weight: .semibold))
                .foregroundStyle(OdeBrandTheme.textDisplay)
                .fixedSize(horizontal: false, vertical: true)
            }
            RoundedRectangle(cornerRadius: OdeCornerScale.control, style: .continuous)
                .strokeBorder(OdeBrandTheme.line, lineWidth: 1)
                .frame(height: 24)
                .overlay(alignment: .leading) {
                    Text("Your Mac's login password")
                        .font(OdeTypography.sans(11, weight: .regular))
                        .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.6))
                        .padding(.leading, 8)
                }
            // The system's own choices, without recommending ongoing access.
            HStack(spacing: 6) {
                pictureButton("Always Allow", isDefault: false)
                Spacer(minLength: 0)
                pictureButton("Deny", isDefault: false)
                pictureButton("Allow", isDefault: true)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(OdeBrandTheme.surface, in: .rect(cornerRadius: OdeCornerScale.surface, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OdeCornerScale.surface, style: .continuous)
                .strokeBorder(OdeBrandTheme.line, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 18, y: 10)
    }

    private func pictureButton(_ title: LocalizedStringKey, isDefault: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: OdeCornerScale.keycap, style: .continuous)
        return Text(title)
            .font(OdeTypography.sans(11, weight: .medium))
            .foregroundStyle(isDefault ? OdeBrandTheme.canvas : OdeBrandTheme.textDisplay)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(isDefault ? AnyShapeStyle(OdeBrandTheme.accent) : AnyShapeStyle(OdeBrandTheme.line), in: shape)
    }
}
