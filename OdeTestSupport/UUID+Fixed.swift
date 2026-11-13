import Foundation

extension UUID {
    /// An identifier that is the same on every run: the ASCII bytes of
    /// `namespace` first, then zeros, then `value` big-endian in the last
    /// bytes. A test file that seeds state other tests can see keeps a
    /// namespace of its own, so its identifiers never meet theirs.
    static func fixed(_ value: some BinaryInteger, namespace: String = "") -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let prefix = Array(namespace.utf8)
        precondition(prefix.count < 16, "A namespace leaves at least one byte for the value.")
        bytes.replaceSubrange(0..<prefix.count, with: prefix)
        var remaining = UInt64(value)
        var index = 15
        while remaining > 0 {
            precondition(index >= prefix.count, "The value does not fit beside its namespace.")
            bytes[index] = UInt8(truncatingIfNeeded: remaining)
            remaining >>= 8
            index -= 1
        }
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
