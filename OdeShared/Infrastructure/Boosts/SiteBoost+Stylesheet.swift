import Foundation

extension SiteBoost {
    // MARK: - Static Variables

    /// The tint's own lightness and chroma in OKLCH; the hue is the Boost's.
    /// Multiplied over a light page it colors the page's white and keeps its
    /// text dark; under the dark filter it colors the dark ground instead.
    static let tintLightness = 0.9
    static let tintChroma = 0.08
    /// Elements a dark page turns back the right way: pictures, video and
    /// embedded documents, which inverting the page would show as negatives.
    /// Vector images stay inverted, since they are mostly logos and icons
    /// drawn dark on a light page.
    static let darkExceptions =
        "html img:not([src*=\".svg\" i]), html video, html canvas, html iframe, html embed, html object, html svg image"
    /// Text a Boost's font leaves alone: code keeps its spacing and icon fonts
    /// keep their glyphs.
    static let fontExceptions =
        "pre, pre *, code, code *, kbd, samp, i, svg, svg *, [class*=\"icon\" i], [class*=\"fa-\"], [class*=\"material-\"], [aria-hidden=\"true\"]"

    // MARK: - Initializers

    /// A Boost for `site` that changes nothing yet, turned on.
    init(blankFor site: String) {
        self.init(
            site: site, isEnabled: true, isDark: false, tintHue: SpaceColorPreset.azure.inputs.hue, tintStrength: 0,
            brightness: 1, contrast: 1, font: nil, hiddenSelectors: [], customCss: "")
    }

    // MARK: - Actions - Styles

    /// Whether the Boost changes anything on its site's pages.
    var changesPages: Bool {
        isDark || tintStrength > 0 || brightness != 1 || contrast != 1 || font != nil || !hiddenSelectors.isEmpty
            || !customCss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The CSS the Boost puts on its site's pages, every declaration marked
    /// important so the page's own rules give way: the filter that darkens,
    /// brightens or adds contrast to the whole page, the tint over it, the
    /// font, a rule that hides each hidden element, and the person's own CSS
    /// last. Empty when the Boost changes nothing.
    var stylesheet: String {
        var rules: [String] = []
        var filters: [String] = []
        if isDark { filters.append("invert(1) hue-rotate(180deg)") }
        if brightness != 1 { filters.append("brightness(\(Self.number(brightness)))") }
        if contrast != 1 { filters.append("contrast(\(Self.number(contrast)))") }
        if !filters.isEmpty { rules.append("html { filter: \(filters.joined(separator: " ")) !important; }") }
        if isDark { rules.append("\(Self.darkExceptions) { filter: invert(1) hue-rotate(180deg) !important; }") }
        if tintStrength > 0 {
            rules.append(
                "html::after { content: \"\" !important; display: block !important; position: fixed !important; "
                    + "inset: 0 !important; pointer-events: none !important; z-index: 2147483647 !important; "
                    + "background: oklch(\(Self.number(Self.tintLightness)) \(Self.number(Self.tintChroma)) "
                    + "\(Self.number(tintHue))) !important; mix-blend-mode: multiply !important; "
                    + "opacity: \(Self.number(tintStrength)) !important; }")
        }
        if let font {
            rules.append(
                "html body, html body *:not(\(Self.fontExceptions)) { font-family: \(font.family) !important; }")
        }
        rules += hiddenSelectors.map { "\($0) { display: none !important; }" }
        if !customCss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rules.append(customCss) }
        return rules.joined(separator: "\n")
    }

    /// A number as CSS spells it, whatever the person's locale.
    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
