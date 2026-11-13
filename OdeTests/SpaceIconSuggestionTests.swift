import AppKit
import Foundation
import XCTest

@testable import Ode

final class SpaceIconSuggestionTests: XCTestCase {
    private static let catalog = BrowserIconCatalog.load(symbolNames: BrowserSystemSymbolCatalog.availableNames())

    /// Forty common Space names with the symbol families and emoji that
    /// suit each, labelled by hand when the suggestions were designed.
    private static let labels: [(name: String, symbols: [String], emoji: [String])] = [
        (
            "Work", ["briefcase", "laptopcomputer", "building.2", "desktopcomputer", "case", "person.crop.rectangle"],
            ["💼", "💻", "🏢", "🖥", "🗂", "📊", "👔"]
        ),
        (
            "Personal", ["person", "house", "heart", "star", "sparkles", "leaf"],
            ["🙂", "🏠", "❤", "⭐", "👤", "🌱", "✨", "😊"]
        ),
        (
            "Travel", ["airplane", "suitcase", "globe", "map", "beach.umbrella", "mappin", "tram", "sailboat", "car"],
            ["✈", "🧳", "🌍", "🌎", "🌏", "🗺", "🏝", "🚆", "🛫", "🧭", "🏖"]
        ),
        (
            "Side project",
            ["hammer", "wrench.and.screwdriver", "lightbulb", "sparkles", "shippingbox", "puzzlepiece"],
            ["🛠", "🔨", "💡", "🧪", "🚀", "🧩"]
        ),
        (
            "Music", ["music.note", "music.note.list", "headphones", "guitars", "pianokeys", "hifispeaker"],
            ["🎵", "🎶", "🎧", "🎸", "🎹", "🎤"]
        ),
        ("Home", ["house", "house.lodge", "sofa", "bed.double", "key"], ["🏠", "🏡", "🛋", "🔑", "🪴"]),
        ("Shopping", ["cart", "bag", "storefront", "creditcard", "tag"], ["🛒", "🛍", "🏬", "💳", "🏷"]),
        (
            "Finance",
            ["dollarsign", "banknote", "creditcard", "chart.line.uptrend.xyaxis", "building.columns", "chart.pie"],
            ["💰", "💵", "💳", "🏦", "📈", "🧾"]
        ),
        (
            "Research", ["magnifyingglass", "flask", "atom", "books.vertical", "text.page.badge.magnifyingglass"],
            ["🔬", "🔍", "🧪", "📚", "📑"]
        ),
        ("School", ["graduationcap", "studentdesk", "book", "backpack", "pencil"], ["🎓", "🏫", "📚", "✏", "🎒", "📝"]),
        ("Reading", ["book", "books.vertical", "eyeglasses", "text.book.closed"], ["📖", "📚", "👓", "🔖"]),
        ("News", ["newspaper", "globe", "antenna.radiowaves.left.and.right"], ["📰", "🗞", "🌐", "📣"]),
        ("Health", ["heart.text.square", "cross.case", "stethoscope", "heart", "pills"], ["🩺", "💊", "🏥", "🫀"]),
        (
            "Fitness", ["figure.run", "dumbbell", "heart", "figure.strengthtraining.traditional", "bicycle"],
            ["🏋", "🏃", "💪", "🚴", "🧘"]
        ),
        ("Cooking", ["frying.pan", "fork.knife", "carrot", "birthday.cake"], ["🍳", "🍲", "🥘", "🔪"]),
        ("Gaming", ["gamecontroller", "arcade.stick", "puzzlepiece", "trophy"], ["🎮", "🕹", "👾", "🎲", "🏆"]),
        ("Design", ["paintpalette", "paintbrush", "pencil.and.ruler", "swatchpalette"], ["🎨", "🖌", "✏", "📐", "🖍"]),
        (
            "Development",
            ["chevron.left.forwardslash.chevron.right", "curlybraces", "apple.terminal", "hammer", "laptopcomputer"],
            ["💻", "⌨", "🐛", "🛠"]
        ),
        ("Photos", ["camera", "photo", "photo.on.rectangle", "camera.aperture"], ["📷", "📸", "🖼", "🌅"]),
        ("Family", ["person.3", "house", "heart", "figure.2.and.child.holdinghands"], ["🏡", "❤", "👪"]),
        ("Friends", ["person.2", "person.3", "bubble.left.and.bubble.right", "heart"], ["👯", "🎉", "💬"]),
        ("Kids", ["figure.and.child.holdinghands", "teddybear", "stroller", "balloon"], ["🧸", "👶", "🎈", "🧒"]),
        ("Learning", ["graduationcap", "book", "lightbulb", "brain"], ["📚", "🎓", "🧠", "💡", "✏"]),
        (
            "Job search", ["text.document", "magnifyingglass", "briefcase", "person.crop.rectangle"],
            ["🔎", "📄", "💼", "🤝", "📝"]
        ),
        ("Writing", ["pencil", "square.and.pencil", "text.document", "text.quote"], ["✍", "✏", "📝", "🖋", "📓"]),
        ("Movies", ["film", "popcorn", "tv", "theatermasks"], ["🎬", "🍿", "🎥", "📽", "🎞"]),
        (
            "Sports", ["sportscourt", "soccerball", "basketball", "tennisball", "trophy", "figure.run"],
            ["⚽", "🏀", "🏈", "🎾", "🏆"]
        ),
        ("Garden", ["leaf", "tree", "camera.macro", "sprinkler"], ["🌱", "🪴", "🌻", "🌳", "🌷"]),
        ("Pets", ["pawprint", "dog", "cat", "fish", "bird"], ["🐶", "🐱", "🐾", "🐠", "🐦"]),
        ("Car", ["car", "steeringwheel", "fuelpump", "wrench.adjustable"], ["🚗", "🏎", "🚙", "🔧", "⛽"]),
        (
            "Startup", ["lightbulb", "chart.line.uptrend.xyaxis", "briefcase", "building.2", "flame"],
            ["🚀", "💡", "📈", "🦄", "💼"]
        ),
        ("Clients", ["person.2", "briefcase", "person.crop.rectangle.stack", "building.2"], ["🤝", "💼", "👥", "📇"]),
        ("Social", ["bubble.left.and.bubble.right", "person.2", "heart", "at"], ["💬", "👥", "📱", "🌐", "❤"]),
        ("Admin", ["gearshape", "folder", "checklist", "text.document", "tray.full"], ["🗂", "📋", "⚙", "🧾", "📎"]),
        ("Wedding", ["heart", "sparkles", "gift", "camera"], ["💍", "💒", "💐", "🥂", "👰"]),
        (
            "Vacation", ["beach.umbrella", "sun.max", "airplane", "suitcase", "sailboat"],
            ["🏖", "🏝", "☀", "🌴", "✈", "🧳"]
        ),
        ("Recipes", ["fork.knife", "frying.pan", "book", "carrot"], ["🍲", "🥘", "📖", "🍳", "🥗"]),
        ("Books", ["books.vertical", "book", "text.book.closed", "bookmark"], ["📚", "📖", "📕", "🔖"]),
        ("Podcasts", ["microphone", "waveform", "headphones", "radio"], ["🎙", "🎧", "📻", "🎤"]),
        ("Art", ["paintpalette", "paintbrush", "photo.artframe", "scribble"], ["🎨", "🖼", "🖌", "🖍"]),
    ]

    private static func plain(_ emoji: String) -> String { emoji.replacingOccurrences(of: "\u{FE0F}", with: "") }

    func testEveryConceptNamesSymbolsAndEmojiTheCatalogHas() throws {
        let catalog = Self.catalog
        XCTAssertGreaterThan(catalog.concepts.count, 100)
        let symbols = Set(catalog.symbolNames)
        let emoji = Set(catalog.emoji.map { Self.plain($0.choice.emoji) })
        for concept in catalog.concepts {
            XCTAssertFalse(concept.terms.isEmpty, concept.id)
            for symbol in concept.symbols {
                XCTAssertTrue(symbols.contains(symbol), "\(concept.id): \(symbol)")
                XCTAssertTrue(BrowserIconCatalog.isSuggestible(symbol), "\(concept.id): \(symbol)")
            }
            for character in concept.emoji {
                XCTAssertTrue(emoji.contains(Self.plain(character)), "\(concept.id): \(character)")
            }
        }
    }

    func testCommonNamesGetFittingIconsInTheirFirstFive() {
        let suggester = SpaceIconSuggester(catalog: Self.catalog)
        var symbolHits = 0
        var emojiHits = 0
        for label in Self.labels {
            let suggestions = suggester.suggestions(for: label.name)
            let families = Set(label.symbols.map(BrowserIconCatalog.family(of:)))
            let emoji = Set(label.emoji.map(Self.plain))
            if suggestions.symbols.prefix(5).contains(where: { families.contains(BrowserIconCatalog.family(of: $0)) }) {
                symbolHits += 1
            }
            if suggestions.emoji.prefix(5).contains(where: { emoji.contains(Self.plain($0)) }) { emojiHits += 1 }
        }
        XCTAssertGreaterThanOrEqual(symbolHits, 25, "symbol hits \(symbolHits) of \(Self.labels.count)")
        XCTAssertGreaterThanOrEqual(emojiHits, 28, "emoji hits \(emojiHits) of \(Self.labels.count)")
    }

    func testTheClearestNamesLeadWithTheObviousIcon() {
        let suggester = SpaceIconSuggester(catalog: Self.catalog)
        XCTAssertEqual(suggester.suggestions(for: "Work").symbols.first, "briefcase")
        XCTAssertEqual(suggester.suggestions(for: "Travel").symbols.first, "airplane")
        XCTAssertEqual(suggester.suggestions(for: "Work").emoji.first.map(Self.plain), "💼")
        XCTAssertEqual(suggester.suggestions(for: "my travel stuff").symbols.first, "airplane")
    }

    func testSuggestionsAreDistinctFamiliesAndNeverRestricted() {
        let suggester = SpaceIconSuggester(catalog: Self.catalog)
        for label in Self.labels {
            let symbols = suggester.suggestions(for: label.name).symbols
            XCTAssertLessThanOrEqual(symbols.count, 8)
            XCTAssertEqual(Set(symbols.map(BrowserIconCatalog.family(of:))).count, symbols.count, label.name)
            for symbol in symbols {
                XCTAssertTrue(BrowserIconCatalog.isSuggestible(symbol), "\(label.name): \(symbol)")
            }
        }
        XCTAssertFalse(BrowserIconCatalog.isSuggestible("0.circle"))
        XCTAssertFalse(BrowserIconCatalog.isSuggestible("a.circle.fill"))
        XCTAssertFalse(BrowserIconCatalog.isSuggestible("iphone"))
        XCTAssertFalse(BrowserIconCatalog.isSuggestible("character.ja"))
    }

    func testAnEmojiInTheNameIsSuggestedFirst() {
        let suggester = SpaceIconSuggester(catalog: Self.catalog)
        XCTAssertEqual(suggester.suggestions(for: "Plants 🪴").emoji.first, "🪴")
    }

    func testSymbolsBrowseWithoutDigitsFirst() {
        let first = Self.catalog.symbolNames.prefix(50)
        XCTAssertFalse(first.contains { $0.first?.isNumber == true })
        XCTAssertFalse(Self.catalog.popularSections.isEmpty)
        XCTAssertTrue(Self.catalog.popularSections[0].symbols.contains("briefcase"))
    }

    /// The shipped catalog preserves the names the running system can draw
    /// without loading each symbol's artwork when the picker opens.
    func testTheCatalogOffersExactlyTheSymbolsTheSystemDraws() {
        let names = BrowserSystemSymbolCatalog.availableNames()
        XCTAssertGreaterThan(names.count, 5_000)
        let drawn = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
        XCTAssertEqual(names, drawn)
    }

    func testVariantsFoldIntoOneFamily() {
        XCTAssertEqual(BrowserIconCatalog.family(of: "briefcase.circle.fill"), "briefcase")
        XCTAssertEqual(BrowserIconCatalog.family(of: "car.2.fill"), "car.2")
        XCTAssertEqual(BrowserIconCatalog.family(of: "dollarsign.circle"), BrowserIconCatalog.family(of: "eurosign"))
    }

    func testTheColorRowRingsTheNearestPresetOnlyWhenClose() {
        XCTAssertEqual(SpaceColorPreset.worn(by: SpaceColorPreset.azure.branding), .azure)
        XCTAssertEqual(SpaceColorPreset.worn(by: SpaceColorPreset.graphite.branding), .graphite)
        var nearAzure = SpaceBranding.neutral
        let swatch = SpaceColorPreset.azure.swatch
        nearAzure.colors = ColorPalette(colors: [
            BrandColor(red: swatch.red + 0.01, green: swatch.green, blue: swatch.blue - 0.01, alpha: 1)
        ])
        XCTAssertEqual(SpaceColorPreset.worn(by: nearAzure), .azure)
        var navy = SpaceBranding.neutral
        navy.colors = ColorPalette(colors: [BrandColor(red: 0.05, green: 0.08, blue: 0.3, alpha: 1)])
        XCTAssertNil(SpaceColorPreset.worn(by: navy))
    }
}
