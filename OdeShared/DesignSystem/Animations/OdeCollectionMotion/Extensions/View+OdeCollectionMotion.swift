import SwiftUI

extension View {
    func odeCollectionMotion<ID: Hashable>(ids: [ID]) -> some View {
        modifier(OdeCollectionMotionModifier(ids: ids))
    }

    func odeCollectionItemTransition() -> some View {
        transition(.opacity)
    }
}
