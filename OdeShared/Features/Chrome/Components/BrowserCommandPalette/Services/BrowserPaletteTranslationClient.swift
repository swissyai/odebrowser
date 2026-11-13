import Foundation
import NaturalLanguage
@preconcurrency import Translation

/// A single-pair, installed-only Apple service boundary. No query cache,
/// downloads, permissions, cloud fallback or all-pairs inventory.
actor BrowserPaletteTranslationClient {
    // MARK: - Static Variables

    static let shared = BrowserPaletteTranslationClient()

    // MARK: - Variables

    private var sessions: [UUID: TranslationSession] = [:]

    // MARK: - Actions - Translation

    func translate(_ lookup: PaletteTranslationLookup) async -> PaletteTranslationResult {
        let sourceID = lookup.sourceLanguage ?? detectedLanguage(in: lookup.text)
        guard let sourceID else { return result(lookup, source: nil, status: .unidentified) }
        guard !BrowserTranslationLanguageCatalog.matches(sourceID, lookup.targetLanguage) else {
            return result(lookup, source: sourceID, status: .sameLanguage)
        }
        let source = Locale.Language(identifier: sourceID)
        let target = Locale.Language(identifier: lookup.targetLanguage)
        // Check only this pair. Prefer an installed low-latency model, but
        // keep an installed standard model usable without downloading another.
        var lowLatencyStatus = LanguageAvailability.Status.unsupported
        if #available(macOS 26.4, iOS 26.4, *) {
            lowLatencyStatus = await BrowserTranslationPreference.languageAvailability(lowLatency: true)
                .status(from: source, to: target)
        }
        let lowLatency = lowLatencyStatus == .installed
        guard !Task.isCancelled else { return result(lookup, source: sourceID, status: .failed) }
        if !lowLatency {
            let status = await BrowserTranslationPreference.languageAvailability(lowLatency: false)
                .status(from: source, to: target)
            guard status == .installed else {
                let unsupported = status == .unsupported && lowLatencyStatus == .unsupported
                return result(lookup, source: sourceID, status: unsupported ? .unsupported : .notInstalled)
            }
        }
        guard !Task.isCancelled else { return result(lookup, source: sourceID, status: .failed) }
        let session: TranslationSession
        if lowLatency, #available(macOS 26.4, iOS 26.4, *) {
            session = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
        let id = UUID()
        sessions[id] = session
        defer {
            session.cancel()
            sessions[id] = nil
        }
        return await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let response = try await session.translate(lookup.text)
                try Task.checkCancellation()
                guard !response.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return result(lookup, source: sourceID, status: .failed)
                }
                return PaletteTranslationResult(
                    lookup: lookup, sourceLanguage: response.sourceLanguage.minimalIdentifier,
                    text: response.targetText, status: .translated)
            } catch TranslationError.notInstalled {
                return result(lookup, source: sourceID, status: .notInstalled)
            } catch TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage,
                TranslationError.unsupportedLanguagePairing
            {
                return result(lookup, source: sourceID, status: .unsupported)
            } catch {
                return result(lookup, source: sourceID, status: .failed)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) { sessions[id]?.cancel() }

    private func result(
        _ lookup: PaletteTranslationLookup, source: String?, status: PaletteTranslationStatus
    ) -> PaletteTranslationResult {
        PaletteTranslationResult(lookup: lookup, sourceLanguage: source, text: nil, status: status)
    }

    private func detectedLanguage(in text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }
}
