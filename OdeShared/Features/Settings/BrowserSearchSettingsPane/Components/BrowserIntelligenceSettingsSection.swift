import SwiftUI

#if os(macOS)
    /// Ode's opt-in tab organization, separate from website search shortcuts.
    struct BrowserIntelligenceSettingsSection: View {
        // MARK: - Static Variables

        private static let manageUsageURL = URL(string: "https://chatgpt.com/settings/usage")!

        // MARK: - Variables

        @AppStorage(BrowserIntelligencePreference.enabledKey)
        private var isEnabled = BrowserIntelligencePreference.defaultEnabled
        @AppStorage(BrowserIntelligencePreference.providerKey)
        private var providerName = BrowserIntelligencePreference.defaultChoice.name
        @AppStorage(BrowserIntelligencePreference.localEndpointKey)
        private var localEndpoint = BrowserIntelligencePreference.defaultLocalEndpoint
        @AppStorage(BrowserIntelligencePreference.localModelKey)
        private var localModel = BrowserIntelligencePreference.defaultLocalModel
        @AppStorage(BrowserIntelligencePreference.tidyTitlesOnPinKey)
        private var tidiesTitlesOnPin = BrowserIntelligencePreference.defaultTidyTitlesOnPin
        @State private var availability: BrowserIntelligenceAvailability?
        @State private var isChecking = false
        @State private var chatGPTCredential: ChatGPTCredential?
        @State private var isSigningIn = false
        @State private var chatGPTError: String?
        @Environment(\.openURL) private var openURL

        private var enabled: OdeSettingValue<Bool> {
            OdeSettingValue($isEnabled, default: BrowserIntelligencePreference.defaultEnabled)
        }
        private var provider: OdeSettingValue<String> {
            OdeSettingValue($providerName, default: BrowserIntelligencePreference.defaultChoice.name)
        }
        private var endpoint: OdeSettingValue<String> {
            OdeSettingValue($localEndpoint, default: BrowserIntelligencePreference.defaultLocalEndpoint)
        }
        private var model: OdeSettingValue<String> {
            OdeSettingValue($localModel, default: BrowserIntelligencePreference.defaultLocalModel)
        }
        private var tidyTitles: OdeSettingValue<Bool> {
            OdeSettingValue($tidiesTitlesOnPin, default: BrowserIntelligencePreference.defaultTidyTitlesOnPin)
        }
        private var choice: BrowserIntelligencePreference.Choice {
            BrowserIntelligencePreference.Choice.named(providerName)
        }

        var body: some View {
            OdeSettingsGroup(
                "Tab organization",
                settings: [
                    enabled.resettable("Enable suggestions"), provider.resettable("Tab organization model"),
                    endpoint.resettable("Endpoint"), model.resettable("Model name"),
                    tidyTitles.resettable("Tidy titles when pinning"),
                ],
                footnote: footnote
            ) {
                OdeSettingRow("Enable suggestions", setting: enabled.resettable("Enable suggestions")) {
                    Toggle("Enable suggestions", isOn: enabled.binding)
                        .labelsHidden()
                        .accessibilityIdentifier("intelligence-enabled")
                }
                .settingsSearchTarget(.intelligence)
                OdeSettingRow("Tab organization model", setting: provider.resettable("Tab organization model")) {
                    Picker("Tab organization model", selection: provider.binding) {
                        ForEach(BrowserIntelligencePreference.Choice.all, id: \.name) { option in
                            Text(option.title).tag(option.name)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("intelligence-provider")
                }
                if isEnabled {
                    if choice.usesLocalEndpoint {
                        localModelRows
                    } else if choice == .chatGPT {
                        chatGPTRows
                    }
                }
                OdeSettingRow("Availability") {
                    HStack(spacing: OdeSpacing.small) {
                        availabilitySummary
                        if isEnabled && choice.usesLocalEndpoint {
                            Button("Check") { Task { await check(choice) } }
                                .disabled(isChecking)
                                .accessibilityIdentifier("intelligence-check")
                        }
                    }
                }
                .task(id: providerName) { await refreshAvailability() }
                if isEnabled {
                    OdeSettingRow(
                        "Tidy titles when pinning", setting: tidyTitles.resettable("Tidy titles when pinning")
                    ) {
                        Toggle("Tidy titles when pinning", isOn: tidyTitles.binding)
                            .labelsHidden()
                            .accessibilityIdentifier("intelligence-tidy-titles-on-pin")
                    }
                }
            }
            .onChange(of: isEnabled) { Task { await refreshAvailability() } }
            .onChange(of: localEndpoint) { availability = nil }
            .onChange(of: localModel) { availability = nil }
        }

        private var footnote: LocalizedStringKey {
            if choice == .chatGPT {
                "Suggests folders for review; can tidy titles when pinning or saving. With ChatGPT, titles and tab names are sent to OpenAI using your plan."
            } else if choice.usesLocalEndpoint {
                "Suggests folders for review; can tidy titles when pinning or saving. Uses the model server you run on this Mac."
            } else {
                "Suggests folders for review; can tidy titles when pinning or saving. Apple’s model runs on this Mac; nothing is sent to an AI service."
            }
        }

        // MARK: - Actions - Local model

        private var localModelRows: some View {
            Group {
                OdeSettingRow("Endpoint", setting: endpoint.resettable("Endpoint")) {
                    TextField(
                        "Endpoint", text: endpoint.binding,
                        prompt: Text(verbatim: BrowserIntelligencePreference.defaultLocalEndpoint)
                    )
                    .labelsHidden()
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("intelligence-local-endpoint")
                }
                OdeSettingRow("Model name", setting: model.resettable("Model name")) {
                    TextField("Model name", text: model.binding, prompt: Text(verbatim: "llama3.2"))
                        .labelsHidden()
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("intelligence-local-model")
                }
            }
        }

        // MARK: - Actions - ChatGPT account

        @ViewBuilder
        private var chatGPTRows: some View {
            if let credential = chatGPTCredential, credential.isSignedIn {
                OdeSettingRow("ChatGPT account") {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let email = credential.email {
                            Text(verbatim: email)
                                .accessibilityIdentifier("intelligence-chatgpt-email")
                        }
                        Text("Using ChatGPT plan")
                            .foregroundStyle(.secondary)
                    }
                }
                OdeSettingRow("Plan") {
                    HStack(spacing: OdeSpacing.small) {
                        Button("Manage usage") { openURL(Self.manageUsageURL) }
                            .accessibilityIdentifier("intelligence-chatgpt-manage-usage")
                        Button("Sign Out") { Task { await signOutOfChatGPT() } }
                            .accessibilityIdentifier("intelligence-chatgpt-sign-out")
                    }
                }
            } else {
                OdeSettingRow("ChatGPT account") {
                    HStack(spacing: OdeSpacing.small) {
                        if isSigningIn {
                            ProgressView().controlSize(.small)
                        }
                        Button("Continue with ChatGPT") { Task { await signInToChatGPT() } }
                            .disabled(isSigningIn)
                            .accessibilityIdentifier("intelligence-chatgpt-sign-in")
                    }
                }
            }
            if let chatGPTError {
                Text(verbatim: chatGPTError)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("intelligence-chatgpt-error")
            }
        }

        private func signInToChatGPT() async {
            isSigningIn = true
            chatGPTError = nil
            let openPage = openURL
            do {
                chatGPTCredential = try await ChatGPTAuthorization.shared.signIn { url in openPage(url) }
            } catch {
                chatGPTError = error.localizedDescription
            }
            isSigningIn = false
            await check(.chatGPT)
        }

        private func signOutOfChatGPT() async {
            chatGPTError = nil
            if await !ChatGPTAuthorization.shared.signOut() {
                chatGPTError = String(
                    localized:
                        "Ode signed out on this Mac but couldn’t confirm it with ChatGPT. You can disconnect Ode in ChatGPT’s settings."
                )
            }
            await check(.chatGPT)
        }

        // MARK: - Actions - Availability

        private var availabilitySummary: some View {
            Group {
                if isChecking {
                    ProgressView().controlSize(.small)
                } else if let availability {
                    Text(availability.summary)
                } else if !isEnabled && choice != .onDevice {
                    Text("Not checked")
                } else if choice.usesLocalEndpoint {
                    Text("Not checked")
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("intelligence-availability")
        }

        private func refreshAvailability() async {
            availability = nil
            // Apple's status is local and does not load or ask the model. Do
            // not contact a server or read an account while the feature is off.
            guard choice == .onDevice || isEnabled && !choice.usesLocalEndpoint else { return }
            await check(choice)
        }

        private func check(_ choice: BrowserIntelligencePreference.Choice) async {
            if choice == .chatGPT {
                chatGPTCredential = ChatGPTCredentialStore.load()
            }
            isChecking = true
            let result = await choice.provider(endpoint: localEndpoint, model: localModel).availability()
            // A slow server check must not label a newly selected model.
            if self.choice == choice && (isEnabled || choice == .onDevice) {
                availability = result
            }
            isChecking = false
        }
    }
#endif
