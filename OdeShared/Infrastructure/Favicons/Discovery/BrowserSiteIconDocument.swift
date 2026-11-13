import Foundation

// MARK: - Types

/// A `<base>` or `<link>` tag of a page's head, by its lowercased name.
private struct HeadTag {
    let name: String
    let attributes: [String: String]
}

/// The icons and web app manifests a page's head declares, read from the
/// first bytes of its HTML without running it: each `<link>` whose `rel`
/// names an icon or a manifest, resolved against the page's `<base>` or its
/// own address. Comments and the contents of scripts, styles, `noscript` and
/// templates are not read, and reading stops where the head ends.
struct BrowserSiteIconDocument: Sendable {
    // MARK: - Static Variables

    /// Elements whose contents are never links of the head.
    private static let skippedElements: [[UInt8]] = ["script", "style", "noscript", "template", "textarea", "title"]
        .map { Array($0.utf8) }
    /// The largest data URL an icon link may carry.
    private static let maximumDataURLLength = 256 * 1_024

    // MARK: - Variables

    let icons: [BrowserSiteIconCandidate]
    let manifestURLs: [URL]

    // MARK: - Initializers

    /// The head of the HTML `data`, which was served from `url`.
    init(html data: Data, url: URL) {
        let tags = Self.tags(in: Array(data))
        var base = url
        if let href = tags.first(where: { $0.name == "base" })?.attributes["href"],
            let resolved = Self.resolve(href, against: url), Self.isWebAddress(resolved)
        {
            base = resolved
        }
        var icons: [BrowserSiteIconCandidate] = []
        var manifests: [URL] = []
        for (order, tag) in tags.enumerated() where tag.name == "link" {
            guard let href = tag.attributes["href"], let target = Self.resolve(href, against: base) else { continue }
            let tokens = Set(
                (tag.attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            if tokens.contains("manifest"), Self.isWebAddress(target), !manifests.contains(target) {
                manifests.append(target)
            }
            guard let relation = BrowserSiteIconRelation.linked(by: tokens),
                Self.isWebAddress(target) || Self.isImageData(target)
            else { continue }
            icons.append(
                BrowserSiteIconCandidate(
                    url: target, relation: relation, sizes: tag.attributes["sizes"], type: tag.attributes["type"],
                    media: tag.attributes["media"], tint: tag.attributes["color"], order: order))
        }
        self.icons = icons
        manifestURLs = manifests
    }

    // MARK: - Actions - Reading

    private static func isWebAddress(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }

    private static func isImageData(_ url: URL) -> Bool {
        let value = url.absoluteString
        return value.count <= maximumDataURLLength && value.lowercased().hasPrefix("data:image/")
    }

    /// `href` resolved against `base`, with surrounding space trimmed and any
    /// character a URL cannot hold escaped.
    private static func resolve(_ href: String, against base: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed, relativeTo: base)?.absoluteURL { return url }
        let allowed = CharacterSet.urlQueryAllowed.union(.urlPathAllowed).union(CharacterSet(charactersIn: "#%"))
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
            .flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
    }

    // MARK: - Actions - Scanning

    /// The `<base>` and `<link>` tags of the head of `bytes`, in order.
    private static func tags(in bytes: [UInt8]) -> [HeadTag] {
        var tags: [HeadTag] = []
        var index = 0
        while let open = bytes[index...].firstIndex(of: UInt8(ascii: "<")) {
            index = open + 1
            if starts(bytes, at: index, with: Array("!--".utf8)) {
                index = find(Array("-->".utf8), in: bytes, from: index + 3).map { $0 + 3 } ?? bytes.count
                continue
            }
            let isClosing = index < bytes.count && bytes[index] == UInt8(ascii: "/")
            let nameStart = isClosing ? index + 1 : index
            var nameEnd = nameStart
            while nameEnd < bytes.count, isNameByte(bytes[nameEnd]) { nameEnd += 1 }
            let name = bytes[nameStart..<nameEnd].map(lowercased)
            guard !name.isEmpty else { continue }
            if isClosing {
                if name == Array("head".utf8) { break }
                continue
            }
            if name == Array("body".utf8) { break }
            let (attributes, end) = attributes(in: bytes, from: nameEnd)
            index = end
            if let skipped = skippedElements.first(where: { $0 == name }) {
                let closing = Array("</".utf8) + skipped
                index = find(closing, in: bytes, from: index, caseInsensitive: true) ?? bytes.count
                continue
            }
            let tagName = String(decoding: name, as: UTF8.self)
            if tagName == "link" || tagName == "base" {
                tags.append(HeadTag(name: tagName, attributes: attributes))
            }
        }
        return tags
    }

    /// The attributes of the tag whose name ends at `start`, and where the tag
    /// ends. A name repeated keeps its first value, as HTML does.
    private static func attributes(in bytes: [UInt8], from start: Int) -> ([String: String], Int) {
        var attributes: [String: String] = [:]
        var index = start
        while index < bytes.count {
            while index < bytes.count, isSpace(bytes[index]) || bytes[index] == UInt8(ascii: "/") { index += 1 }
            guard index < bytes.count, bytes[index] != UInt8(ascii: ">") else { break }
            let nameStart = index
            while index < bytes.count, !isSpace(bytes[index]),
                ![UInt8(ascii: "="), UInt8(ascii: ">"), UInt8(ascii: "/")].contains(bytes[index])
            {
                index += 1
            }
            let name = String(decoding: bytes[nameStart..<index].map(lowercased), as: UTF8.self)
            while index < bytes.count, isSpace(bytes[index]) { index += 1 }
            var value = ""
            if index < bytes.count, bytes[index] == UInt8(ascii: "=") {
                index += 1
                while index < bytes.count, isSpace(bytes[index]) { index += 1 }
                if index < bytes.count, bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'") {
                    let quote = bytes[index]
                    let valueStart = index + 1
                    let valueEnd = bytes[valueStart...].firstIndex(of: quote) ?? bytes.count
                    value = decodeEntities(String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self))
                    index = min(valueEnd + 1, bytes.count)
                } else {
                    let valueStart = index
                    while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: ">") { index += 1 }
                    value = decodeEntities(String(decoding: bytes[valueStart..<index], as: UTF8.self))
                }
            }
            if !name.isEmpty, attributes[name] == nil { attributes[name] = value }
        }
        return (attributes, min(index + 1, bytes.count))
    }

    /// `value` with the character references a URL or a token list can carry
    /// replaced by their characters.
    private static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = ""
        var rest = Substring(value)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let reference = rest[rest.index(after: ampersand)...]
            guard let semicolon = reference.prefix(10).firstIndex(of: ";") else {
                result += "&"
                rest = reference
                continue
            }
            let name = reference[..<semicolon].lowercased()
            let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">"]
            if let character = named[name] {
                result += character
            } else if name.hasPrefix("#x"), let code = UInt32(name.dropFirst(2), radix: 16),
                let scalar = Unicode.Scalar(code)
            {
                result.unicodeScalars.append(scalar)
            } else if name.hasPrefix("#"), let code = UInt32(name.dropFirst()), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else {
                result += "&"
                rest = reference
                continue
            }
            rest = reference[reference.index(after: semicolon)...]
        }
        return result + rest
    }

    private static func find(
        _ needle: [UInt8], in bytes: [UInt8], from start: Int, caseInsensitive: Bool = false
    ) -> Int? {
        guard !needle.isEmpty, start <= bytes.count - needle.count else { return nil }
        var index = start
        while index <= bytes.count - needle.count {
            if caseInsensitive
                ? startsIgnoringCase(bytes, at: index, with: needle) : starts(bytes, at: index, with: needle)
            {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func starts(_ bytes: [UInt8], at index: Int, with prefix: [UInt8]) -> Bool {
        index + prefix.count <= bytes.count && bytes[index..<(index + prefix.count)].elementsEqual(prefix)
    }

    private static func startsIgnoringCase(_ bytes: [UInt8], at index: Int, with prefix: [UInt8]) -> Bool {
        guard index + prefix.count <= bytes.count else { return false }
        for offset in prefix.indices where lowercased(bytes[index + offset]) != lowercased(prefix[offset]) {
            return false
        }
        return true
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "-")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        [UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\t"), UInt8(ascii: "\r"), 0x0C].contains(byte)
    }
}
