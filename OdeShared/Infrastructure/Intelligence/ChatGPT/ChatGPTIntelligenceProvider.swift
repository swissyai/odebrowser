import Foundation

/// The person's own ChatGPT plan through Sign in with ChatGPT. Each request
/// carries only the instructions and the prompt a feature built, and goes to
/// OpenAI's Responses API under the person's plan.
struct ChatGPTIntelligenceProvider: BrowserIntelligenceProvider {
    // MARK: - Static Variables

    static let modelsURL = URL(string: "https://api.openai.com/v1/models")!
    static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    static let usageLimitCode = "subscription_sharing_usage_limit_exceeded"
    static let notEligibleCode = "subscription_sharing_user_not_eligible"
    static let unavailableCodes: Set<String> = [
        "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable",
    ]
    static let timeout: TimeInterval = 60

    private static let catalog = ModelCatalog()
    private static var session: URLSession { ChatGPTNetwork.session }

    // MARK: - Types

    enum Failure: LocalizedError {
        case planNotAllowed
        case usageLimit
        case notEligible
        case unavailable
        case noModels
        case unexpectedStatus(Int)
        case failed(String?)
        case incomplete
        case unreadableAnswer

        var errorDescription: String? {
            switch self {
            case .planNotAllowed:
                String(localized: "Your sign-in didn’t allow Ode to use your ChatGPT plan. Sign out and allow it.")
            case .usageLimit:
                String(localized: "Your ChatGPT usage limit is reached.")
            case .notEligible:
                String(localized: "Your ChatGPT plan can’t be used in Ode.")
            case .unavailable:
                String(localized: "ChatGPT isn’t available right now. Try again later.")
            case .noModels:
                String(localized: "Your ChatGPT plan offers no models.")
            case .unexpectedStatus(let status):
                String(localized: "ChatGPT answered with status \(status).")
            case .failed(let message):
                message ?? String(localized: "ChatGPT couldn’t answer.")
            case .incomplete:
                String(localized: "ChatGPT stopped before finishing its answer. Try again.")
            case .unreadableAnswer:
                String(localized: "ChatGPT’s answer couldn’t be read.")
            }
        }
    }

    /// A Responses request as plan usage requires it: streamed, and never
    /// stored on OpenAI's side.
    private struct ResponseRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let instructions: String
        let input: [Message]
        let store: Bool
        let stream: Bool
    }

    /// The models the signed-in account may use, in the server's order.
    private struct ModelCatalogResponse: Decodable {
        struct Model: Decodable {
            let slug: String
            let visibility: String?
        }

        let models: [Model]
    }

    private struct Problem: Decodable {
        let code: String?
        let message: String?
    }

    /// An API error, or the plain detail an admission refusal carries
    /// before a response starts.
    private struct ErrorBody: Decodable {
        let error: Problem?
        let detail: String?
    }

    /// One server-sent event of a streamed response.
    private struct StreamEvent: Decodable {
        struct Response: Decodable {
            let error: Problem?
        }

        let type: String
        let delta: String?
        let response: Response?
        let code: String?
        let message: String?
    }

    /// The models the plan offers, listed once per launch.
    private actor ModelCatalog {
        private var task: Task<[String], any Error>?

        func ids(listing list: @escaping @Sendable () async throws -> [String]) async throws -> [String] {
            if let task { return try await task.value }
            let listing = Task { try await list() }
            task = listing
            do {
                return try await listing.value
            } catch {
                task = nil
                throw error
            }
        }
    }

    // MARK: - Actions - Availability

    /// Ready only once the person is signed in with a grant to use their
    /// plan; a sign-in that granted only their identity isn't enough.
    func availability() async -> BrowserIntelligenceAvailability {
        guard let credential = ChatGPTCredentialStore.load(), credential.isSignedIn else {
            return BrowserIntelligenceAvailability(
                isAvailable: false, summary: String(localized: "Continue with ChatGPT to use your plan."))
        }
        guard credential.scopes.contains(ChatGPTAuthorization.planScope) else {
            return BrowserIntelligenceAvailability(
                isAvailable: false, summary: Failure.planNotAllowed.localizedDescription)
        }
        return BrowserIntelligenceAvailability(
            isAvailable: true, summary: String(localized: "Ready to use your ChatGPT plan."))
    }

    // MARK: - Actions - Completion

    func complete(instructions: String, prompt: String) async throws -> String {
        let credential = try await ChatGPTAuthorization.shared.currentCredential()
        guard let accessToken = credential.accessToken else { throw ChatGPTAuthorization.Failure.signedOut }
        guard credential.scopes.contains(ChatGPTAuthorization.planScope) else { throw Failure.planNotAllowed }
        let body = ResponseRequest(
            model: try await model(accessToken: accessToken), instructions: instructions,
            input: [ResponseRequest.Message(role: "user", content: prompt)], store: false, stream: true)
        var request = Self.authorized(Self.responsesURL, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await Self.session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.failure(status: status, body: data)
        }
        var text = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONDecoder().decode(StreamEvent.self, from: Data(payload.utf8)) else { continue }
            switch event.type {
            case "response.output_text.delta":
                text += event.delta ?? ""
            case "response.completed":
                return text
            case "response.failed":
                throw Self.failure(event.response?.error)
            case "response.incomplete":
                throw Failure.incomplete
            case "error":
                throw Self.failure(Problem(code: event.code, message: event.message))
            default:
                continue
            }
        }
        // A stream that ends without its terminal event was interrupted.
        throw Failure.incomplete
    }

    // MARK: - Actions - Requests

    /// The model in the preference, or else the first model the account
    /// lists, in the order the server gives.
    private func model(accessToken: String) async throws -> String {
        let chosen = (UserDefaults.standard.string(forKey: BrowserIntelligencePreference.chatGPTModelKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !chosen.isEmpty { return chosen }
        let ids = try await Self.catalog.ids { try await Self.modelIDs(accessToken: accessToken) }
        guard let first = ids.first else { throw Failure.noModels }
        return first
    }

    private static func modelIDs(accessToken: String) async throws -> [String] {
        var request = authorized(modelsURL, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw failure(status: status, body: data) }
        guard let catalog = try? JSONDecoder().decode(ModelCatalogResponse.self, from: data) else {
            throw Failure.unreadableAnswer
        }
        return catalog.models.filter { $0.visibility == "list" && !$0.slug.isEmpty }.map(\.slug)
    }

    private static func authorized(_ url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// What a refused request means for the person. A 401 does not prove
    /// the sign-in was revoked, so the saved tokens are kept.
    private static func failure(status: Int, body: Data) -> any Error {
        let decoded = try? JSONDecoder().decode(ErrorBody.self, from: body)
        if let problem = decoded?.error, problem.code != nil { return failure(problem) }
        switch status {
        case 401: return ChatGPTAuthorization.Failure.signedOut
        case 403: return Failure.notEligible
        case 503: return Failure.unavailable
        default: return Failure.unexpectedStatus(status)
        }
    }

    private static func failure(_ problem: Problem?) -> any Error {
        switch problem?.code {
        case usageLimitCode?: Failure.usageLimit
        case notEligibleCode?: Failure.notEligible
        case let code? where unavailableCodes.contains(code): Failure.unavailable
        default: Failure.failed(problem?.message)
        }
    }
}
