import Foundation

extension AgentJSON {
    // MARK: - Actions - Page Responses

    /// The value read as `Value`, or the failure that says the page answered
    /// something else.
    func decoded<Value: Decodable>(_: Value.Type) throws(BrowserAgentFailure) -> Value {
        guard let value = try? decoded(as: Value.self) else {
            throw .refused("The page answered something Ode can’t read.")
        }
        return value
    }
}
