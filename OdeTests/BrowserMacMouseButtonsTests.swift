import AppKit
import XCTest

@testable import Ode

@MainActor
final class BrowserMacMouseButtonsTests: XCTestCase {
    // MARK: - Types

    /// A window's content that takes the presses it is offered while
    /// `takesPresses` says so.
    private final class Content: BrowserMacWindowPointerNavigation {
        var takesPresses: Bool
        private(set) var presses: [BrowserSidebarMouseButtonAction] = []

        init(takesPresses: Bool) {
            self.takesPresses = takesPresses
        }

        func takePress(_ action: BrowserSidebarMouseButtonAction, at event: NSEvent) -> Bool {
            presses.append(action)
            return takesPresses
        }

        func navigate(_ action: BrowserSidebarMouseButtonAction, swipedAt event: NSEvent) -> Bool {
            false
        }
    }

    // MARK: - Actions - Tests

    /// Chromium goes back or forward again on a Back or Forward release it
    /// sees, so the release of a press Ode acted on must never reach the
    /// page, even when SwiftUI rebuilt the window's content in between.
    func testTakenClickIsTakenWholeAfterTheWindowContentIsRebuilt() throws {
        var content: Content? = Content(takesPresses: true)
        let buttons = BrowserMacMouseButtons(navigation: { _ in content })

        XCTAssertTrue(buttons.take(try event(.otherMouseDown, button: 3)))
        XCTAssertEqual(content?.presses, [.previousSpace])
        content = nil

        XCTAssertTrue(buttons.take(try event(.otherMouseDragged, button: 3)))
        XCTAssertTrue(buttons.take(try event(.otherMouseUp, button: 3)))
        XCTAssertFalse(buttons.take(try event(.otherMouseUp, button: 3)))
    }

    /// A click the window's content lets go reaches the page whole, even
    /// after a taken press whose release the application never saw.
    func testClickTheContentLetsGoReachesThePageWhole() throws {
        let content = Content(takesPresses: true)
        let buttons = BrowserMacMouseButtons(navigation: { _ in content })
        XCTAssertTrue(buttons.take(try event(.otherMouseDown, button: 4)))

        content.takesPresses = false
        XCTAssertFalse(buttons.take(try event(.otherMouseDown, button: 4)))
        XCTAssertFalse(buttons.take(try event(.otherMouseDragged, button: 4)))
        XCTAssertFalse(buttons.take(try event(.otherMouseUp, button: 4)))
        XCTAssertFalse(buttons.take(try event(.otherMouseDown, button: 2)))
        XCTAssertFalse(buttons.take(try event(.otherMouseUp, button: 2)))
        XCTAssertEqual(content.presses, [.nextSpace, .nextSpace])
    }

    // MARK: - Actions - Events

    private func event(_ type: CGEventType, button: Int64) throws -> NSEvent {
        let event = try XCTUnwrap(
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: .center))
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }
}
