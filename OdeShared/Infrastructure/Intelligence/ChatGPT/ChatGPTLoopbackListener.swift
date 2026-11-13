import Foundation
import Network

/// An HTTP listener on 127.0.0.1 that waits for the one redirect a sign-in
/// expects: a request to the callback path carrying this attempt's state.
/// Any other request is answered and ignored, so nothing else on the Mac can
/// end the sign-in. Every property is touched on `queue` only.
final class ChatGPTLoopbackListener: @unchecked Sendable {
    // MARK: - Variables

    private let queue = DispatchQueue(label: "\(ProductIdentity.serviceNamespace).chatgpt.loopback")
    private let state: String
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var ready: CheckedContinuation<UInt16, any Error>?
    private var waiting: CheckedContinuation<[String: String], any Error>?
    private var result: Result<[String: String], any Error>?

    // MARK: - Initializers

    init(state: String) {
        self.state = state
    }

    // MARK: - Actions - Listening

    /// Listens on `port`, or on any free port when that one is taken, and
    /// returns the port it got.
    func start(preferring port: UInt16) async throws -> UInt16 {
        do {
            return try await listen(on: NWEndpoint.Port(rawValue: port) ?? .any)
        } catch {
            return try await listen(on: .any)
        }
    }

    private func listen(on port: NWEndpoint.Port) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        let listener = try NWListener(using: parameters)
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                self.listener = listener
                self.ready = continuation
                listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: self.queue)
            }
        }
    }

    /// The query of the callback request that carries this attempt's state.
    func callback(timeout: TimeInterval) async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.queue.async {
                    if let result = self.result {
                        continuation.resume(with: result)
                    } else {
                        self.waiting = continuation
                    }
                }
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(ChatGPTAuthorization.Failure.timedOut))
                }
            }
        } onCancel: {
            self.queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue ?? 0
            ready?.resume(returning: port)
            ready = nil
        case .failed, .waiting:
            listener?.cancel()
            if let ready {
                listener = nil
                self.ready = nil
                ready.resume(throwing: ChatGPTAuthorization.Failure.listener)
            } else {
                finish(.failure(ChatGPTAuthorization.Failure.listener))
            }
        default:
            break
        }
    }

    /// Keeps the first result and hands it to whoever waits for it.
    private func finish(_ outcome: Result<[String: String], any Error>) {
        guard result == nil else { return }
        result = outcome
        waiting?.resume(with: outcome)
        waiting = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    /// Reads until the end of the request head, then answers it.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) == nil, !isComplete, error == nil, buffer.count < 65_536 {
                self.receive(on: connection, buffer: buffer)
                return
            }
            self.answer(connection, request: buffer)
        }
    }

    private func answer(_ connection: NWConnection, request: Data) {
        let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        let host = lines.dropFirst().first { $0.lowercased().hasPrefix("host:") }
            .map { $0.dropFirst("host:".count).trimmingCharacters(in: .whitespaces) }
        let components = parts.count >= 2 ? URLComponents(string: "http://127.0.0.1\(parts[1])") : nil
        let items = components?.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        let status: String
        let message: String
        if parts.first != "GET" || host != "127.0.0.1:\(port)" || components?.path != ChatGPTAuthorization.callbackPath
            || result != nil
        {
            status = "404 Not Found"
            message = ""
        } else if states.count != 1 || states.first?.value != state {
            status = "400 Bad Request"
            message = String(localized: "This sign-in link is out of date. Return to Ode and try again.")
        } else {
            var query: [String: String] = [:]
            for item in items where query[item.name] == nil {
                query[item.name] = item.value ?? ""
            }
            finish(.success(query))
            status = "200 OK"
            message = String(localized: "You can close this tab and return to Ode.")
        }
        let body = Data("<!doctype html><meta charset=\"utf-8\"><p>\(message)</p>".utf8)
        let head =
            [
                "HTTP/1.1 \(status)",
                "Content-Type: text/html; charset=utf-8",
                "Cache-Control: no-store",
                "Referrer-Policy: no-referrer",
                "Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
                "Content-Length: \(body.count)",
                "Connection: close",
            ].joined(separator: "\r\n") + "\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
