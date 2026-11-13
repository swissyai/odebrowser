import Foundation

/// A model the person already runs on this Mac behind an OpenAI-compatible
/// endpoint, such as Ollama or LM Studio. Only a loopback endpoint is ever
/// contacted and redirects are refused, so no request can reach a remote host.
struct LocalModelIntelligenceProvider: BrowserIntelligenceProvider {
    // MARK: - Static Variables

    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
    static let timeout: TimeInterval = 30
    static let temperature = 0.2

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }()
    private static let redirectRefusal = RedirectRefusal()

    // MARK: - Variables

    let endpoint: String
    let model: String

    // MARK: - Types

    enum Failure: LocalizedError {
        case invalidEndpoint
        case remoteEndpoint
        case missingModel
        case unexpectedStatus(Int)
        case unreadableAnswer

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                String(localized: "The endpoint isn’t a valid http address.")
            case .remoteEndpoint:
                String(localized: "The endpoint must be on this Mac: 127.0.0.1, localhost or ::1.")
            case .missingModel:
                String(localized: "Enter the name of a model to use.")
            case .unexpectedStatus(let status):
                String(localized: "The model server answered with status \(status).")
            case .unreadableAnswer:
                String(localized: "The model server’s answer couldn’t be read.")
            }
        }
    }

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    /// Keeps every request at the address it was sent to: a loopback server
    /// that redirects elsewhere gets its redirect answer back as the response.
    private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    // MARK: - Actions - Availability

    /// Lists the models the server offers and whether the chosen one is
    /// among them.
    func availability() async -> BrowserIntelligenceAvailability {
        let names: [String]
        do {
            var request = URLRequest(url: try address(appending: "models"), timeoutInterval: Self.timeout)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let list = try await data(for: request)
            names = try JSONDecoder().decode(ModelList.self, from: list).data.map(\.id)
        } catch {
            return BrowserIntelligenceAvailability(isAvailable: false, summary: error.localizedDescription)
        }
        let found = names.formatted(.list(type: .and))
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !names.isEmpty else {
            return BrowserIntelligenceAvailability(
                isAvailable: false, summary: String(localized: "The model server has no models."))
        }
        guard !trimmedModel.isEmpty else {
            return BrowserIntelligenceAvailability(
                isAvailable: false, summary: String(localized: "Found \(found). Enter one of them as the model."))
        }
        // Ollama answers to a model name without a tag as its latest tag.
        guard names.contains(trimmedModel) || names.contains("\(trimmedModel):latest") else {
            return BrowserIntelligenceAvailability(
                isAvailable: false, summary: String(localized: "That model isn’t running here. Found \(found)."))
        }
        return BrowserIntelligenceAvailability(isAvailable: true, summary: String(localized: "Found \(found)."))
    }

    // MARK: - Actions - Completion

    func complete(instructions: String, prompt: String) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw Failure.missingModel }
        let body = ChatRequest(
            model: trimmedModel,
            messages: [
                ChatRequest.Message(role: "system", content: instructions),
                ChatRequest.Message(role: "user", content: prompt),
            ],
            stream: false,
            temperature: Self.temperature)
        var request = URLRequest(url: try address(appending: "chat/completions"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let reply = try await data(for: request)
        let answer = try? JSONDecoder().decode(ChatResponse.self, from: reply)
        guard let content = answer?.choices.first?.message.content else { throw Failure.unreadableAnswer }
        return content
    }

    // MARK: - Actions - Requests

    /// The endpoint with a path appended, refused unless it is an http
    /// address on a loopback host.
    private func address(appending path: String) throws -> URL {
        guard
            let base = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = base.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = base.host
        else { throw Failure.invalidEndpoint }
        let bareHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard Self.loopbackHosts.contains(bareHost) else { throw Failure.remoteEndpoint }
        return base.appending(path: path)
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.session.data(for: request, delegate: Self.redirectRefusal)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.unreadableAnswer }
        guard (200...299).contains(status) else { throw Failure.unexpectedStatus(status) }
        return data
    }
}
