import Foundation

/// Recognizes one horizontal Space intent without coupling selection to scroll position.
/// Phased gestures stay latched until their boundary; phase-less devices use a quiet gap
/// measured from the last event, never a timer measured from the last accepted step.
struct SpaceScrollGestureRecognizer {
    enum Phase: Equatable, Sendable {
        case none, mayBegin, began, changed, ended, cancelled

        /// Ends the gesture it belongs to, whatever its delta.
        var isTerminal: Bool { self == .ended || self == .cancelled }
        /// Keeps a phased gesture open across quiet gaps.
        var isActive: Bool { self == .began || self == .changed }
    }

    struct Input: Equatable, Sendable {
        let deltaX: CGFloat
        let deltaY: CGFloat
        let timestamp: TimeInterval
        let isPrecise: Bool
        let phase: Phase
        let isMomentum: Bool

        var isFinite: Bool { deltaX.isFinite && deltaY.isFinite && timestamp.isFinite }
    }

    private enum Axis {
        case undecided, horizontal, vertical, outside

        /// Whether travel along this axis can still become, or already is, a swipe.
        var tracksTravel: Bool { self == .undecided || self == .horizontal }
    }

    /// Precise deltas are points; ordinary wheel deltas are line units. These are
    /// separate recognition thresholds, not a conversion tied to the tab-row height.
    private struct Units {
        static let precise = Units(threshold: 40, recognitionDistance: 8)
        static let wheel = Units(threshold: 1, recognitionDistance: 0.25)
        static let horizontalDominance: CGFloat = 1.35

        static func of(_ input: Input) -> Units { input.isPrecise ? .precise : .wheel }

        /// The distance along the decided axis that completes a step.
        let threshold: CGFloat
        /// The distance that decides the axis.
        let recognitionDistance: CGFloat

        func clamped(_ value: CGFloat) -> CGFloat {
            let limit = threshold * 100
            return min(limit, max(-limit, value))
        }

        /// The axis the accumulated travel leans along, or nil while it leans
        /// along neither by enough. Vertical travel wins a tie.
        func dominantAxis(x: CGFloat, y: CGFloat) -> Axis? {
            if abs(y) >= recognitionDistance, abs(y) >= abs(x) * Self.horizontalDominance { return .vertical }
            if abs(x) >= recognitionDistance, abs(x) >= abs(y) * Self.horizontalDominance { return .horizontal }
            return nil
        }
    }

    private static let phaseLessIdleInterval: TimeInterval = 0.35

    private var axis: Axis = .undecided
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var initialDirection: CGFloat = 0
    private var hasResolved = false
    private var hasActivePhase = false
    private var hasFinished = false
    private var lastTimestamp: TimeInterval?

    /// A finished or terminal event belongs to the swipe only when it claimed
    /// the horizontal axis.
    private var claimedDecision: Decision { axis == .horizontal ? .consumed : .passThrough }

    mutating func reset() {
        self = Self()
    }

    /// Disabling recognition must reject the current stream without inventing
    /// a new gesture when it becomes enabled again. Retain its phase and clock.
    mutating func cancelCurrentGesture() {
        axis = .outside
        hasResolved = true
    }

    mutating func consume(_ input: Input, isInside: Bool) -> Decision {
        guard input.isFinite else {
            reset()
            return .passThrough
        }
        guard input.phase != .mayBegin else { return .passThrough }

        // Momentum can arrive after a zero-delta .ended, or with no ordinary
        // phase at all. It never starts a new recognition, even after a long gap.
        if input.isMomentum { return finish(at: input.timestamp) }

        if startsGesture(input) {
            reset()
            axis = isInside ? .undecided : .outside
        }
        lastTimestamp = input.timestamp

        // Terminal events must run before nonzero-delta and axis filters, and
        // still belong to a claimed gesture after the pointer leaves the region.
        if input.phase.isTerminal { return finish(at: input.timestamp) }
        if hasFinished { return claimedDecision }
        if input.phase.isActive { hasActivePhase = true }
        guard axis.tracksTravel else { return .passThrough }
        if hasResolved { return .consumed }
        return recognize(input, units: .of(input))
    }

    /// A began phase starts a new gesture, as does a phase-less event after a
    /// quiet gap or the first event ever; an open phased gesture never does.
    private func startsGesture(_ input: Input) -> Bool {
        guard input.phase != .began, let lastTimestamp else { return true }
        return !hasActivePhase && input.timestamp - lastTimestamp > Self.phaseLessIdleInterval
    }

    private mutating func finish(at timestamp: TimeInterval) -> Decision {
        lastTimestamp = timestamp
        hasActivePhase = false
        hasFinished = true
        return claimedDecision
    }

    /// Adds the event's travel, decides the axis once, and steps when the
    /// horizontal travel passes the threshold in its first direction.
    private mutating func recognize(_ input: Input, units: Units) -> Decision {
        accumulatedX = units.clamped(accumulatedX + input.deltaX)
        accumulatedY = units.clamped(accumulatedY + input.deltaY)

        if axis == .undecided {
            guard let decided = units.dominantAxis(x: accumulatedX, y: accumulatedY) else { return .passThrough }
            axis = decided
            guard decided == .horizontal else { return .passThrough }
            initialDirection = accumulatedX < 0 ? -1 : 1
        }

        // Returning across the origin before acceptance abandons this candidate.
        // It does not select the opposite Space later in the same gesture.
        guard accumulatedX * initialDirection > 0 else {
            hasResolved = true
            return .consumed
        }
        guard abs(accumulatedX) >= units.threshold else { return .consumed }
        hasResolved = true
        return .step(initialDirection < 0 ? .next : .previous)
    }
}
