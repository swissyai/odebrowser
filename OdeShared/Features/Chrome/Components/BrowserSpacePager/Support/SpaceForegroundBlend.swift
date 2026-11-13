import SwiftUI

extension EnvironmentValues {
    @Entry var spaceChromeAccent: Color? = nil
    @Entry var spaceChromeForeground: Color? = nil
}

/// Fixed chrome follows visible Space progress without observing it in tab
/// rows: its text and accent blend between the role colors of the Spaces the
/// pager shows.
struct SpaceForegroundBlend: ViewModifier {
    // MARK: - Variables

    let ids: [UUID]
    let brandings: [SpaceBranding]
    let colorInputs: [SpaceColorInputs]
    let selectedSpaceID: UUID?

    @Environment(\.spacePagerPresentation) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var foreground = SpaceForegroundPresentation()

    /// Each Space's text tone in the windows' appearance.
    private var tones: [SpaceForegroundPresentation.Tone] {
        zip(ids, brandings).map { id, branding in
            SpaceForegroundPresentation.Tone(id: id, white: branding.foregroundTone == .light ? 1 : 0)
        }
    }

    /// Each Space's index in the order the pager's position runs along.
    private var arrangement: [Int] {
        guard let order = foreground.order else { return Array(ids.indices) }
        let indices = order.compactMap { ids.firstIndex(of: $0) }
        return indices.count == ids.count ? indices : Array(ids.indices)
    }

    // MARK: - Initializers

    init(spaces: [SpaceModel], selectedSpaceID: UUID?) {
        ids = spaces.map(\.id)
        brandings = spaces.map(\.settings.look)
        colorInputs = brandings.map(\.colorInputs)
        self.selectedSpaceID = selectedSpaceID
    }

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        let tones = tones
        let arrangement = arrangement
        let roles = colorInputs.map {
            SpaceColorRoles($0, colorScheme: colorScheme, increasedContrast: contrast == .increased)
        }
        content
            .modifier(
                SpaceForegroundTone(
                    position: foreground.position ?? CGFloat(tones.firstIndex { $0.id == selectedSpaceID } ?? 0),
                    texts: arrangement.map { roles[$0].text.color },
                    accents: arrangement.map { roles[$0].accentText.color })
            )
            .onAppear { foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID) }
            .onChange(of: tones) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onChange(of: selectedSpaceID) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onChange(of: presentation.map(ObjectIdentifier.init)) { _, _ in
                foreground.connect(presentation, tones: tones, selectedSpaceID: selectedSpaceID)
            }
            .onDisappear { foreground.disconnect() }
    }
}

private struct SpaceForegroundTone: ViewModifier, Animatable {
    nonisolated var position: CGFloat
    let texts: [Color]
    let accents: [Color]

    nonisolated var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        let foreground = blend(texts) ?? .primary
        content
            .foregroundStyle(foreground)
            .environment(\.spaceChromeForeground, foreground)
            .environment(\.spaceChromeAccent, blend(accents))
    }

    /// `colors` at the pager's position, mixed between the two Spaces it
    /// sits between.
    private func blend(_ colors: [Color]) -> Color? {
        guard let sample = SpacePagerInterpolation(position: position, count: colors.count) else { return nil }
        return colors[sample.lower].mix(with: colors[sample.upper], by: Double(sample.fraction), in: .perceptual)
    }
}
