import SwiftUI

// The practice actions the guides offer for the tabs chapter's lessons. Each
// guide switches on the lesson's kind to choose one of these concrete views.

/// Pins the practice Gmail tab.
struct BrowserGettingStartedPinAction: View {
    // MARK: - Variables

    let practice: BrowserGettingStartedPractice
    var style: OdeButtonStyle = .odePrimary(tint: OdeBrandPalette.butter)

    // MARK: - Actions - Presentation

    var body: some View {
        Button {
            if let mail = practice.tabID(.mail) { practice.browser.pinTab(mail) }
        } label: {
            Label("Pin Gmail", systemImage: "pin.fill")
                .font(.body.weight(.semibold))
                .frame(minHeight: OdeLayout.minimumHitTarget)
        }
        .buttonStyle(style)
    }
}

/// Saves the practice trail tab, worded the way each guide words it.
struct BrowserGettingStartedSaveAction: View {
    // MARK: - Variables

    let practice: BrowserGettingStartedPractice
    let title: LocalizedStringKey
    let systemImage: String
    var style: OdeButtonStyle = .odePrimary(tint: OdeBrandPalette.butter)

    // MARK: - Actions - Presentation

    var body: some View {
        Button {
            if let trail = practice.tabID(.trail) { practice.browser.saveTab(trail) }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(minHeight: OdeLayout.minimumHitTarget)
        }
        .buttonStyle(style)
    }
}

/// Adds a practice folder, and one nested inside it. The two buttons join the
/// guide's own stack, so each guide lays them out its way.
struct BrowserGettingStartedFolderActions: View {
    let practice: BrowserGettingStartedPractice

    var body: some View {
        Button("Add folder", systemImage: "folder.badge.plus") { practice.addFolder(nested: false) }
            .buttonStyle(.odeSecondary)
        Button("Nest a folder", systemImage: "folder") { practice.addFolder(nested: true) }
            .buttonStyle(.odeSecondary)
    }
}

/// Points to Clear on the practice sidebar's line, where a pointer reaches it.
struct BrowserGettingStartedClearHint: View {
    var body: some View {
        Text("Use Clear on the line in the practice sidebar.")
            .font(OdeTypography.sans(12)).foregroundStyle(.secondary)
    }
}

/// Archives the practice Space's open tabs, as its ••• menu does.
struct BrowserGettingStartedCleanUpAction: View {
    let practice: BrowserGettingStartedPractice

    var body: some View {
        Button("Clean Up Current Tabs", systemImage: "sparkles") {
            _ = practice.tabActions.clearCurrentTabs()
        }
        .buttonStyle(.odePrimary(tint: OdeBrandPalette.butter))
    }
}
