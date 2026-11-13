import CoreGraphics

/// How densely the sidebar draws its rows and pins, from the person's size
/// settings: the tab or icon scale, which sizes text and icons too, and the
/// layout density, which sizes only the rows and the gaps between them.
struct BrowserSidebarDensity: Equatable, Sendable {
    // MARK: - Static Variables

    static let scaleRange: ClosedRange<Double> = 0.7...1.4
    private static let pointerBodySize: CGFloat = 13
    private static let touchBodySize: CGFloat = 17
    private static let minimumTouchTarget: CGFloat = 44
    private static let minimumPointerTarget: CGFloat = 24
    private static let minimumPointerPinHeight: CGFloat = 32
    private static let basePinHeight: CGFloat = 47
    private static let basePinWidth: CGFloat = 36
    private static let basePinSpacing: CGFloat = 8
    private static let minimumSpacing: CGFloat = 2

    // MARK: - Variables

    /// The setting as stored, before it is held to `scaleRange`.
    let value: Double
    let density: BrowserLayoutDensity

    /// The setting held to `scaleRange`, or 1 when it is not a number.
    var scale: Double {
        value.isFinite ? min(max(value, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) : 1
    }

    /// The space kept between pinned tiles, at this density.
    var pinSpacing: Double { max(Self.minimumSpacing, Self.basePinSpacing * scale * density.gapScale) }

    // MARK: - Initializers

    init(_ value: Double, density: BrowserLayoutDensity = .defaultValue) {
        self.value = value
        self.density = density
    }

    // MARK: - Actions - Layout

    static func bodySize(touch: Bool) -> CGFloat {
        touch ? touchBodySize : pointerBodySize
    }

    func rowHeight(base: CGFloat, touch: Bool) -> CGFloat {
        max(touch ? Self.minimumTouchTarget : Self.minimumPointerTarget, base * scale * density.rowScale)
    }

    func rowSeparation(hasBorders: Bool = false) -> Double {
        value <= 1 || hasBorders ? Self.minimumSpacing : 0
    }

    func pinHeight(touch: Bool) -> Double {
        max(
            touch ? Self.minimumTouchTarget : Self.minimumPointerPinHeight,
            Self.basePinHeight * scale * density.rowScale)
    }

    func pinMinimumWidth(touch: Bool) -> Double {
        max(touch ? Self.minimumTouchTarget : Self.minimumPointerTarget, Self.basePinWidth * scale)
    }
}
