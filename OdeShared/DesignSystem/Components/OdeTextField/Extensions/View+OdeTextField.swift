import SwiftUI

extension View {
    /// Adds Ode chrome to a `TextField` or `SecureField` while preserving the
    /// native field, keyboard, cursor, selection, autofill, submit behavior,
    /// and accessibility role.
    func odeTextField() -> some View {
        textFieldStyle(.plain)
            .modifier(OdeFieldSurface())
    }

    /// Applies the field surface to a field-like row, such as a glyph beside a
    /// plain field, whose field's focus the caller tracks.
    func odeFieldSurface(isFocused: Bool) -> some View {
        modifier(OdeFieldSurface(rowFocus: isFocused))
    }

    /// Tells the fields under this view which surface they sit on.
    func odeFieldSurfaceRole(_ role: OdeFieldSurfaceRole) -> some View {
        environment(\.odeFieldSurfaceRole, role)
    }
}
