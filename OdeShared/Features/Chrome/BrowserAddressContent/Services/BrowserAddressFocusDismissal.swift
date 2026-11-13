import Foundation

enum BrowserAddressFocusDismissal {
    static let notification = Notification.Name(
        "com.odebrowser.ode.dismiss-address-focus"
    )

    static func dismiss() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}
