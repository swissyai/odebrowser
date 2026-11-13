import Darwin
import Foundation

@testable import Ode

/// An agent's link to the browser over a connected socket pair, standing in
/// for the helper process on this one. Closing it releases the tabs the link
/// drove and closes both ends.
@MainActor
final class AgentLinkFixture {
    // MARK: - Variables

    let link: BrowserMacAgents.Link
    private let peerDescriptor: Int32
    private var isClosed = false

    // MARK: - Initializers

    /// A link for the agent session `sessionID`, or for none.
    init(sessionID: UUID? = nil) throws {
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.ENOTCONN) }
        peerDescriptor = descriptors[1]
        let peer = BrowserAgentPeer(helperProcessID: getpid(), agent: nil)
        link = BrowserMacAgents.Link(connection: BrowserAgentConnection(descriptor: descriptors[0], peer: peer))
        link.sessionID = sessionID
    }

    // MARK: - Actions - Lifecycle

    func close() {
        guard !isClosed else { return }
        isClosed = true
        for tabID in link.drivenTabs { BrowserAgentOriginGate.sessions.release(tabID, by: link.gate) }
        link.connection.close()
        Darwin.close(peerDescriptor)
    }
}
