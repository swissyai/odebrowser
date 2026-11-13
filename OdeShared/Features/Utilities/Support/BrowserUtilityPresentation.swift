import Foundation

enum BrowserUtilityPresentation {
    static let noResultsTitle: LocalizedStringResource = "No Results"
    static let noFilteredItemsDescription: LocalizedStringResource =
        "No items match the selected filter."
    static func historyVisits(
        host: String,
        count: Int
    ) -> LocalizedStringResource {
        "\(host) · \(max(count, 0)) visits"
    }
}
