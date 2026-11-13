import SwiftUI

struct BrowserSoftwareUpdateSettingsSection: View {
    // MARK: - Variables

    @Environment(BrowserSoftwareUpdateService.self) private var softwareUpdates
    @State private var isChoosingEarlierVersion = false

    // Bindings take explicit closures: a bare method reference here makes swift-frontend 6.3.3
    // (Xcode 26.6) crash while generating the isolated reabstraction thunk.
    var body: some View {
        Section {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { softwareUpdates.automaticallyChecksForUpdates },
                    set: { softwareUpdates.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .settingsSearchTarget(.automaticUpdates)

            automaticDownloadToggle

            Toggle(
                "Restart to update when this Mac is idle",
                isOn: Binding(
                    get: { softwareUpdates.restartsWhenIdle },
                    set: { softwareUpdates.restartsWhenIdle = $0 }
                )
            )
            .help("After five minutes without input, never during a download or while media plays")
            .settingsSearchTarget(.idleRestart)

            Picker(
                "Update channel",
                selection: Binding(
                    get: { softwareUpdates.channel },
                    set: { softwareUpdates.channel = $0 }
                )
            ) {
                ForEach(BrowserSoftwareUpdateChannel.offered) { channel in
                    Text(channel.title).tag(channel)
                }
            }
            .settingsSearchTarget(.updateChannel)

            if softwareUpdates.model.phase == .idle {
                HStack {
                    Spacer()
                    Button("Check for updates…") {
                        softwareUpdates.checkForUpdates()
                    }
                    .disabled(!softwareUpdates.isEnabled)
                }
            } else {
                BrowserSoftwareUpdateStatusRow(model: softwareUpdates.model)
                BrowserSoftwareUpdateActions(model: softwareUpdates.model, confirmsWithReturn: false)
            }

            if let localFeed = softwareUpdates.localFeedURL {
                LabeledContent("Test feed on this Mac") {
                    Text(verbatim: localFeed.absoluteString)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Use the published feed") {
                        softwareUpdates.stopUsingLocalFeed()
                    }
                }
            }

            if softwareUpdates.isEnabled {
                HStack {
                    Spacer()
                    Button("Go back to an earlier version…") {
                        isChoosingEarlierVersion = true
                    }
                    .disabled(!softwareUpdates.canGoBack)
                    .help(
                        softwareUpdates.rollback.unavailableReason
                            ?? (softwareUpdates.canGoBack
                                ? String(localized: "Download an earlier version and restart into it")
                                : String(localized: "Restart to finish the update first")))
                }
                .settingsSearchTarget(.earlierVersion)
            }

            if let startErrorDescription = softwareUpdates.startErrorDescription {
                Label(
                    startErrorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(OdeColor.warning)
            }
        } header: {
            Text("Software updates")
        } footer: {
            Text(softwareUpdates.channel.guidance).odeFormFootnote()
        }
        .onAppear { softwareUpdates.refreshLocalFeed() }
        .sheet(isPresented: $isChoosingEarlierVersion) {
            BrowserEarlierVersionsSheet(rollback: softwareUpdates.rollback) {
                isChoosingEarlierVersion = false
            }
        }
    }
    // MARK: - Actions - Automatic downloads

    private var automaticDownloadToggle: some View {
        Toggle(
            "Download and install updates automatically",
            isOn: Binding(
                get: { softwareUpdates.automaticallyDownloadsUpdates },
                set: { softwareUpdates.setAutomaticallyDownloadsUpdates($0) }
            )
        )
        .disabled(!softwareUpdates.automaticallyChecksForUpdates)
        .settingsSearchTarget(.automaticInstall)
        .help(
            "Turning this off stops future automatic downloads. Updates already prepared can still install when you quit."
        )
    }

}
