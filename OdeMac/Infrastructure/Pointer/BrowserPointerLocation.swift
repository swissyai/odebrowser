import AppKit

/// Where the pointer is on the screens, for the views that ask rather than
/// wait for an event: the sidebar's hover tracking. A test host fixes it far
/// from every window, so the person's own pointer never reaches a test, and a
/// test that needs the pointer somewhere sets it there.
@MainActor
enum BrowserPointerLocation {
    /// The pointer as the screens see it.
    static var current: () -> NSPoint = { NSEvent.mouseLocation }

    /// A place no window of a test host's is ever under.
    static let outsideEveryWindow = NSPoint(x: -100_000, y: -100_000)
}
