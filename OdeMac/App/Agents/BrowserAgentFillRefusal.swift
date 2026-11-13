import Foundation

/// Why the page would not ready an element for an agent to fill, as the
/// fill script names it, or why Ode keeps an agent from writing into a
/// field at all, from the field's type and autocomplete attribute; and what
/// the agent hears.
struct BrowserAgentFillRefusal: Sendable {
    // MARK: - Static Variables

    /// The page has no element by the uid the agent gave.
    static let unknownElement = Self(name: "unknown") { uid, _ in .unknownElement(uid) }
    /// The element is a menu with no option the value names.
    static let noOption = Self(name: "option") { _, value in
        .refused("The menu has no option labelled or valued \(value).")
    }
    /// The element takes no text.
    static let notEditable = Self(name: "editable") { _, _ in .notEditable }
    /// The element chooses files, which only the person does.
    static let fileInput = Self(name: "file") { _, _ in
        .refused(
            "That element chooses files from the person’s Mac, which agents never do. "
                + "The person must choose the file; ask them to.")
    }

    /// The page's focus is in a frame of another site or a component's closed
    /// shadow root, whose field Ode can't see, so it can't tell whether only
    /// the person fills it.
    static let unseenField = Self(name: "unseen") { _, _ in
        .refused(
            "The focus is in a frame from another site or a closed part of the page, where Ode can’t see which "
                + "field takes the text. Ask the person to type it, or for a frame, open its address in its own tab.")
    }

    static let all: [BrowserAgentFillRefusal] = [unknownElement, noOption, notEditable, unseenField]

    /// The autocomplete tokens of fields only the person fills, beside every
    /// payment card token, which starts with `protectedPrefix`. An outline
    /// never shows such a field's value.
    static let protectedTokens: Set<String> = ["current-password", "new-password", "one-time-code"]
    static let protectedPrefix = "cc-"

    // MARK: - Variables

    let name: String
    private let explanation: @Sendable (_ uid: String, _ value: String) -> BrowserAgentFailure

    // MARK: - Initializers

    private init(name: String, explanation: @escaping @Sendable (_ uid: String, _ value: String) -> BrowserAgentFailure)
    {
        self.name = name
        self.explanation = explanation
    }

    // MARK: - Actions - Failures

    /// The refusal the fill script named `name`, or nil when it named none
    /// Ode knows.
    static func named(_ name: String?) -> Self? {
        all.first { $0.name == name }
    }

    /// The element is a field for a password, a one-time code or a payment
    /// card, as its type or autocomplete token `kind` says, which only the
    /// person fills.
    static func protectedField(_ kind: String) -> Self {
        Self(name: "protected") { _, _ in
            .refused(
                "That field is marked \(kind): it takes a password, a one-time code or payment card details, "
                    + "which agents never type. The person must fill it in; ask them to.")
        }
    }

    /// The refusal for writing into a field whose input type is `type` and
    /// whose autocomplete attribute is `autocomplete`, both lowercased, or nil
    /// when an agent may write into it.
    static func protecting(type: String, autocomplete: String) -> Self? {
        if type == "file" { return fileInput }
        if type == "password" { return protectedField(type) }
        let token = autocomplete.split(whereSeparator: \.isWhitespace).first {
            protectedTokens.contains(String($0)) || $0.hasPrefix(protectedPrefix)
        }
        return token.map { protectedField(String($0)) }
    }

    /// The failure the agent hears for filling element `uid` with `value`.
    func failure(uid: String, value: String) -> BrowserAgentFailure {
        explanation(uid, value)
    }
}
