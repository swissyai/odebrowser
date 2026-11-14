#if DEBUG || ODE_REVIEW_BUILD

    import Darwin
    import Foundation

    /// The harness's socket: a Unix domain socket in the isolated session's
    /// folder, readable only by this user, that answers each line of JSON with
    /// one line of JSON. A connection's commands run one after another.
    final class BrowserMacHarnessServer: @unchecked Sendable {
        typealias Handler = @MainActor @Sendable (Data) async -> Data

        private let listener: Int32
        private let handler: Handler

        /// Listens at `name` in `directory`; nil when the socket cannot be made.
        /// The folder's path is longer than a socket address holds, so the
        /// socket is bound relative to the folder and clients connect from it.
        init?(directory: URL, name: String, handler: @escaping Handler) {
            let path = directory.appendingPathComponent(name).path
            unlink(path)
            let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socket >= 0 else { return nil }
            let folder = open(directory.path, O_RDONLY | O_DIRECTORY)
            defer { if folder >= 0 { close(folder) } }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let nameBytes = Array(name.utf8)
            guard folder >= 0, nameBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                close(socket)
                return nil
            }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                buffer.copyBytes(from: nameBytes)
                buffer[nameBytes.count] = 0
            }
            let length = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Self.bind(socket, $0, length, relativeTo: folder)
                }
            }
            guard bound == 0, chmod(path, 0o600) == 0, listen(socket, 4) == 0 else {
                close(socket)
                return nil
            }
            listener = socket
            self.handler = handler
            let thread = Thread { [self] in acceptLoop() }
            thread.name = "Ode harness"
            thread.start()
        }

        /// Binds `socket` to a name relative to the folder `folder` names:
        /// through `bindat` where libSystem has it, else from inside the folder.
        private static func bind(
            _ socket: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t, relativeTo folder: Int32
        ) -> Int32 {
            typealias BindAt = @convention(c) (Int32, Int32, UnsafePointer<sockaddr>, socklen_t) -> Int32
            if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "bindat") {
                return unsafeBitCast(symbol, to: BindAt.self)(folder, socket, address, length)
            }
            let previous = open(".", O_RDONLY)
            defer {
                if previous >= 0 {
                    fchdir(previous)
                    close(previous)
                }
            }
            guard fchdir(folder) == 0 else { return -1 }
            return Darwin.bind(socket, address, length)
        }

        private func acceptLoop() {
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else {
                    if errno == EINTR { continue }
                    return
                }
                let thread = Thread { [self] in serve(client) }
                thread.name = "Ode harness client"
                thread.start()
            }
        }

        /// Reads lines from `client` and answers each before reading on.
        private func serve(_ client: Int32) {
            defer { close(client) }
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = read(client, &buffer, buffer.count)
                guard count > 0 else { return }
                pending.append(contentsOf: buffer[0..<count])
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    guard !line.isEmpty else { continue }
                    var reply = answer(Data(line))
                    reply.append(0x0A)
                    let sent = reply.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                    guard sent == reply.count else { return }
                }
            }
        }

        /// Runs the handler on the main actor and waits for its reply on this
        /// connection's own thread.
        private func answer(_ request: Data) -> Data {
            let box = ReplyBox()
            let done = DispatchSemaphore(value: 0)
            let handler = handler
            Task { @MainActor in
                box.data = await handler(request)
                done.signal()
            }
            done.wait()
            return box.data
        }

        private final class ReplyBox: @unchecked Sendable {
            var data = Data()
        }
    }

#endif
