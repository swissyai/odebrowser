import SwiftUI

/// A button of a written answer in the Command Bar: "Do it", which runs what
/// the answer names, and "Read more", which opens the guide it comes from.
/// Each says whether an answer offers it and runs itself for that answer in a
/// palette, answering whether it ran. Tab moves between the buttons an answer
/// offers, in `all` order, and Return runs the one Tab is on.
@MainActor
struct BrowserCommandPaletteAnswerControl: Equatable {
    // MARK: - Static Variables

    static let doIt = BrowserCommandPaletteAnswerControl(
        name: "doIt", title: "Do It", hint: "Runs what the answer describes",
        isOffered: { card, palette in palette.canPerformAnswerAction(of: card) },
        perform: { card, palette in palette.performAnswerAction(of: card) })
    static let readMore = BrowserCommandPaletteAnswerControl(
        name: "readMore", title: "Read More", hint: "Opens the guide in a new tab",
        isOffered: { card, palette in !palette.isDirectFeedbackAction(card) },
        perform: { card, palette in palette.openGuide(of: card) ? .performed : .unsupported })

    static let all = [doIt, readMore]

    // MARK: - Variables

    nonisolated let name: String
    let title: LocalizedStringResource
    /// What VoiceOver says the button does.
    let hint: LocalizedStringResource
    private let offers: (AnswerCard, BrowserCommandPaletteModel) -> Bool
    private let perform:
        @MainActor (AnswerCard, BrowserCommandPaletteModel) -> BrowserCommandPaletteCommandRegistry.Result

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, hint: LocalizedStringResource,
        isOffered: @escaping (AnswerCard, BrowserCommandPaletteModel) -> Bool,
        perform:
            @escaping @MainActor (AnswerCard, BrowserCommandPaletteModel) -> BrowserCommandPaletteCommandRegistry.Result
    ) {
        self.name = name
        self.title = title
        self.hint = hint
        offers = isOffered
        self.perform = perform
    }

    // MARK: - Actions - Offering

    /// The buttons `card` offers, in Tab order.
    static func offered(for card: AnswerCard, in palette: BrowserCommandPaletteModel) -> [Self] {
        all.filter { $0.isOffered(for: card, in: palette) }
    }

    func isOffered(for card: AnswerCard, in palette: BrowserCommandPaletteModel) -> Bool {
        offers(card, palette)
    }

    // MARK: - Actions - Running

    /// Runs the button for `card` in `palette`, answering whether it ran.
    func run(_ card: AnswerCard, _ palette: BrowserCommandPaletteModel) -> BrowserCommandPaletteCommandRegistry.Result {
        guard isOffered(for: card, in: palette) else { return .unsupported }
        return perform(card, palette)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
}
