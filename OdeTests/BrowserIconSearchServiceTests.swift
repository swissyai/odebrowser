import Foundation
import XCTest

@testable import Ode

final class BrowserIconSearchServiceTests: XCTestCase {
    /// Result count and first eight symbols for a fixed set of queries.
    private static let expected: [String: (count: Int, top: [String])] = [
        "work": (
            29,
            [
                "briefcase",
                "brain",
                "building.2",
                "chart.bar",
                "desktopcomputer",
                "laptopcomputer",
                "moon",
                "person.crop.rectangle",
            ],
        ),
        "home": (
            103,
            [
                "house",
                "house.lodge",
                "sofa",
                "bed.double",
                "figure.2.and.child.holdinghands",
                "hammer",
                "key",
                "paintbrush.pointed",
            ],
        ),
        "arrow": (
            400,
            [
                "arrow.2.squarepath",
                "arrow.3.trianglepath",
                "arrow.backward",
                "arrow.backward.circle",
                "arrow.backward.square",
                "arrow.backward.circle.fill",
                "arrow.backward.square.fill",
                "arrow.backward.circle.dotted",
            ],
        ),
        "briefcase": (
            33,
            [
                "briefcase",
                "briefcase.fill",
                "briefcase.circle",
                "briefcase.circle.fill",
                "briefcase.sensor.tag.radiowaves.left.and.right",
                "briefcase.sensor.tag.radiowaves.left.and.right.fill",
                "airplane",
                "bag",
            ],
        ),
        "car": (
            400,
            [
                "car",
                "car.fill",
                "car.circle",
                "car.circle.fill",
                "car.2",
                "car.2.fill",
                "car.badge.gearshape",
                "car.badge.gearshape.fill",
            ],
        ),
        "heart fill": (
            16,
            [
                "heart.fill",
                "heart.circle.fill",
                "heart.square.fill",
                "heart.rectangle.fill",
                "heart.badge.bolt.fill",
                "heart.badge.bolt.slash.fill",
                "heart.slash.fill",
                "heart.slash.circle.fill",
            ],
        ),
        "wifi": (
            18,
            [
                "wifi",
                "wifi.circle",
                "wifi.square",
                "wifi.circle.fill",
                "wifi.square.fill",
                "wifi.badge.lock",
                "wifi.exclamationmark",
                "wifi.exclamationmark.circle",
            ],
        ),
        "zzzz": (
            6,
            [
                "moon.zzz",
                "moon.zzz.fill",
                "speaker.zzz",
                "speaker.zzz.fill",
                "zzz",
                "puzzlepiece",
            ],
        ),
        "br": (
            400,
            [
                "brain",
                "brain.fill",
                "brain.filled.head.profile",
                "brain.head.profile",
                "brain.head.profile.fill",
                "brakesignal",
                "brakesignal.dashed",
                "brazilianrealsign.arrow.trianglehead.counterclockwise.rotate.90",
            ],
        ),
    ]

    func testSearchResultsAndOrderAreStable() async {
        let service = BrowserIconSearchService()
        for (query, want) in Self.expected {
            let results = await service.symbols(matching: query)
            XCTAssertEqual(results.count, want.count, query)
            XCTAssertEqual(Array(results.prefix(8)), want.top, query)
        }
    }

    /// Availability is the name list alone: a name the system cannot draw is
    /// kept, so no lookup asked the system to render anything.
    func testAvailabilityComesFromTheNameListWithoutRendering() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "symbols-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "// header\nnot.a.real.symbol.name\nbriefcase\nnot.a.real.symbol.name\n"
            .write(to: folder.appending(path: "SFSymbolNames.txt"), atomically: true, encoding: .utf8)
        let bundle = try XCTUnwrap(Bundle(url: folder))
        let names = BrowserSystemSymbolCatalog.availableNames(bundle: bundle)
        XCTAssertEqual(names, ["not.a.real.symbol.name", "briefcase"])
    }

    func testClosingThePickerReleasesTheCatalogAndTheNextOpenRebuildsIt() async {
        let loads = LoadCounter()
        let service = BrowserIconSearchService(loadSymbolNames: {
            loads.next()
            return ["briefcase", "house"]
        })
        let before = await service.isCatalogLoaded
        XCTAssertFalse(before, "nothing loads before a picker opens")
        _ = await service.loadedCatalog()
        _ = await service.symbols(matching: "house")
        let open = await service.isCatalogLoaded
        XCTAssertTrue(open)
        XCTAssertEqual(loads.count, 1)
        await service.releaseCatalog()
        let closed = await service.isCatalogLoaded
        XCTAssertFalse(closed, "closing drops the catalog and its searchers")
        let results = await service.symbols(matching: "house")
        XCTAssertEqual(results.first, "house")
        XCTAssertEqual(loads.count, 2, "the second open rebuilds lazily")
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func next() { lock.withLock { value += 1 } }
}
