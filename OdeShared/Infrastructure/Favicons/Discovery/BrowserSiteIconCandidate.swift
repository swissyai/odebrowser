import Foundation

/// One icon a site offers for a page, with what the site says of it, ranked
/// for a tab that wears one image in every size and appearance: an icon at
/// least `largeSide` pixels square, or one that scales, comes first, and of
/// those one for any appearance and the kind a browser shows best.
struct BrowserSiteIconCandidate: Hashable, Sendable {
    // MARK: - Static Variables

    /// The smallest side, in pixels, that stays sharp on a pinned tab's tile
    /// at every scale.
    static let largeSide = 64
    /// The side a large icon is best near: twice the largest tile in pixels.
    private static let idealSide = 128.0

    // MARK: - Variables

    let url: URL
    let relation: BrowserSiteIconRelation
    /// The largest side the site declares, or 0 when it declares none.
    let declaredSide: Int
    /// Whether the site declares the icon square, or declares no size.
    let isDeclaredSquare: Bool
    /// Whether the icon scales: an SVG, or one declared for `any` size.
    let isScalable: Bool
    /// How well the icon's `media` suits a tab that shows it on light and
    /// dark grounds alike: one for any appearance first, then light, then
    /// dark.
    let appearanceRank: Int
    /// The color Safari fills a silhouette with, for a mask icon.
    let tint: String?
    /// Where the icon was declared, earlier first.
    let order: Int

    /// Whether the site says this icon is large enough without fetching it.
    var isDeclaredLarge: Bool {
        isScalable || (declaredSide >= Self.largeSide && isDeclaredSquare)
    }

    // MARK: - Initializers

    init(
        url: URL, relation: BrowserSiteIconRelation, sizes: String? = nil, type: String? = nil,
        media: String? = nil, tint: String? = nil, order: Int
    ) {
        self.url = url
        self.relation = relation
        let declared = Self.declaredSizes(sizes)
        declaredSide = declared.map { max($0.width, $0.height) }.max() ?? 0
        isDeclaredSquare = declared.isEmpty || declared.contains { $0.width == $0.height }
        let lowercasedType = type?.lowercased()
        isScalable =
            sizes?.lowercased().split(whereSeparator: \.isWhitespace).contains("any") == true
            || lowercasedType == "image/svg+xml"
            || url.pathExtension.lowercased() == "svg"
            || url.absoluteString.lowercased().hasPrefix("data:image/svg+xml")
        appearanceRank = Self.appearanceRank(media: media)
        self.tint = tint
        self.order = order
    }

    // MARK: - Actions - Ranking

    /// Whether this icon is tried before `other`.
    func precedes(_ other: BrowserSiteIconCandidate) -> Bool {
        rank > other.rank
    }

    /// The order icons are tried in, greatest first: by size class, then
    /// appearance; large icons by kind and then nearness to the ideal side,
    /// icons of unknown size by kind, small ones by size and then kind; then
    /// the earlier declared.
    private var rank: (Int, Int, Double, Double, Int) {
        let sizeClass = sizeClass
        let primary = sizeClass == 0 ? Double(declaredSide) : Double(relation.preference)
        let secondary = sizeClass == 2 ? -distanceFromIdeal : sizeClass == 0 ? Double(relation.preference) : 0
        return (sizeClass, appearanceRank, primary, secondary, -order)
    }

    /// Large or scalable icons first, then icons of unknown size, then those
    /// the site declares small.
    private var sizeClass: Int {
        if isDeclaredLarge { return 2 }
        return declaredSide == 0 ? 1 : 0
    }

    private var distanceFromIdeal: Double {
        isScalable ? 0 : abs(log2(Double(max(declaredSide, 1)) / Self.idealSide))
    }

    // MARK: - Actions - Reading

    /// The sizes a `sizes` attribute declares, such as `16x16 32x32`.
    private static func declaredSizes(_ value: String?) -> [(width: Int, height: Int)] {
        (value ?? "").lowercased().split(whereSeparator: \.isWhitespace).compactMap { size in
            let sides = size.split(separator: "x")
            guard sides.count == 2, let width = Int(sides[0]), let height = Int(sides[1]), width > 0, height > 0
            else { return nil }
            return (width, height)
        }
    }

    /// 2 for an icon with no appearance condition, 1 for one made for light
    /// grounds and 0 for one made for dark grounds.
    static func appearanceRank(media: String?) -> Int {
        let condition = (media ?? "").lowercased().filter { !$0.isWhitespace }
        let dark = condition.contains("prefers-color-scheme:dark")
        let light = condition.contains("prefers-color-scheme:light")
        if dark == light { return 2 }
        return light ? 1 : 0
    }
}
