import XCTest

@testable import Ode

/// Getting Started's everyday moves say exactly what the Command Bar's
/// written answers say, keep what the person did across launches, and hear
/// about the moves from the features themselves.
@MainActor
final class BrowserGettingStartedMovesTests: XCTestCase {
    func testEachMoveUsesItsAnswerCardsWordsAndKeys() throws {
        let answers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "OdeCore/src/OdeCore/Domain/Answers/answers.json")
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: answers)) as? [String: Any])
        let cards = try XCTUnwrap(document["cards"] as? [[String: Any]])
        let byID = Dictionary(
            uniqueKeysWithValues: cards.compactMap { card in (card["id"] as? String).map { ($0, card) } })

        XCTAssertEqual(BrowserGettingStartedMove.allCases.count, 7)
        for move in BrowserGettingStartedMove.allCases {
            let card = try XCTUnwrap(byID[move.answerID], "No answer card \(move.answerID)")
            XCTAssertEqual(card["status"] as? String, "live", move.answerID)
            XCTAssertEqual(move.title, card["title"] as? String, move.answerID)
            XCTAssertEqual(move.steps, card["steps"] as? [String], move.answerID)
            XCTAssertEqual(move.keys, card["keys"] as? String, move.answerID)
        }
    }

    func testShowMeRunsOnlyCommandsThatStartTheMove() {
        XCTAssertEqual(BrowserGettingStartedMove.commandBar.demonstration, .newTab)
        XCTAssertEqual(BrowserGettingStartedMove.splitView.demonstration, .splitWithNextTab)
        XCTAssertEqual(BrowserGettingStartedMove.switchSpace.demonstration, .nextSpace)
        XCTAssertNil(BrowserGettingStartedMove.peek.demonstration, "Peek needs a link on a page.")
        XCTAssertNil(BrowserGettingStartedMove.boost.demonstration, "A Boost needs a website on screen.")
    }

    func testMovesAreKeptAcrossLaunchesAndStartOver() throws {
        let suite = "GettingStartedMovesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let moves = BrowserGettingStartedMoves(defaults: defaults)
        XCTAssertEqual(moves.next, .commandBar)
        moves.record(.commandBar)
        moves.record(.peek)
        moves.record(.peek)
        XCTAssertEqual(moves.next, .siteSearch)

        let relaunched = BrowserGettingStartedMoves(defaults: defaults)
        XCTAssertEqual(relaunched.done, [.commandBar, .peek])

        relaunched.reset()
        XCTAssertTrue(BrowserGettingStartedMoves(defaults: defaults).done.isEmpty)
    }

    func testTheCommandBarReportsASiteOrAnAssistantEnteredWithTab() throws {
        let previous = BrowserGettingStartedMoves.current
        defer { BrowserGettingStartedMoves.current = previous }
        let moves = BrowserGettingStartedMoves(defaults: nil)
        BrowserGettingStartedMoves.current = moves

        BrowserGettingStartedMoves.record(.siteSearch)
        XCTAssertEqual(moves.done, [.siteSearch])
        BrowserGettingStartedMoves.current = nil
        BrowserGettingStartedMoves.record(.askAI)
        XCTAssertEqual(moves.done, [.siteSearch], "Without a launch record nothing is kept.")
    }
}
