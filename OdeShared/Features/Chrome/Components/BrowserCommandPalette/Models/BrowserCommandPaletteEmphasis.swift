import Foundation

/// Which part of a row's title the Command Bar sets in bold: the runs the
/// core marked for what was typed, the words a search suggestion adds to it,
/// as "what is the **odyssey about**" reads, or the parts of a tab's or
/// page's title that match it. Other rows keep their title as one weight.
enum BrowserCommandPaletteEmphasis {
    // MARK: - Actions - Emphasis

    /// `row`'s title with the runs the core marked set as strongly
    /// emphasized, or nil for a row whose title keeps one weight. A run that
    /// does not fall inside the title is left out.
    static func title(of row: PaletteRow) -> AttributedString? {
        guard let emphasis = row.emphasis else { return nil }
        var text = AttributedString(row.title)
        let units = row.title.utf16
        for run in emphasis.runs where run.start >= 0 && run.length > 0 && run.length <= units.count - run.start {
            let lower = units.index(units.startIndex, offsetBy: run.start)
            let upper = units.index(lower, offsetBy: run.length)
            if let range = Range(lower..<upper, in: text) { text[range].inlinePresentationIntent = .stronglyEmphasized }
        }
        return text
    }
}
