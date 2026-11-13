import Foundation

/// The icons a web app manifest lists, read leniently: an entry this cannot
/// read is skipped rather than failing the rest. Maskable and monochrome
/// icons are installation artwork, padded for a mask or drawn in one color,
/// so only those for `any` purpose, the default, are offered to a tab.
struct BrowserSiteIconManifest: Decodable, Sendable {
    // MARK: - Types

    private struct Icon: Decodable, Sendable {
        let source: String?
        let sizes: String?
        let type: String?
        let purpose: String?

        private enum CodingKeys: String, CodingKey {
            case source = "src"
            case sizes, type, purpose
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = try? container.decode(String.self, forKey: .source)
            sizes = try? container.decode(String.self, forKey: .sizes)
            type = try? container.decode(String.self, forKey: .type)
            purpose = try? container.decode(String.self, forKey: .purpose)
        }
    }

    /// One entry of `icons`, or nil when it is not an icon this can read.
    private struct LenientIcon: Decodable, Sendable {
        let icon: Icon?

        init(from decoder: any Decoder) throws {
            icon = try? Icon(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case icons
    }

    // MARK: - Variables

    private let icons: [Icon]

    // MARK: - Initializers

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        icons = ((try? container.decode([LenientIcon].self, forKey: .icons)) ?? []).compactMap(\.icon)
    }

    // MARK: - Actions - Reading

    /// The icons the manifest `data`, served from `url`, offers a tab, or none
    /// when it is not a manifest.
    static func candidates(in data: Data, url: URL) -> [BrowserSiteIconCandidate] {
        guard let manifest = try? JSONDecoder().decode(BrowserSiteIconManifest.self, from: data) else { return [] }
        return manifest.icons.enumerated().compactMap { order, icon in
            let purposes = Set((icon.purpose ?? "any").lowercased().split(whereSeparator: \.isWhitespace))
            guard purposes.contains("any"), let source = icon.source,
                let iconURL = URL(string: source.trimmingCharacters(in: .whitespaces), relativeTo: url)?.absoluteURL,
                ["http", "https"].contains(iconURL.scheme?.lowercased())
            else { return nil }
            return BrowserSiteIconCandidate(
                url: iconURL, relation: .manifest, sizes: icon.sizes, type: icon.type, order: order)
        }
    }
}
