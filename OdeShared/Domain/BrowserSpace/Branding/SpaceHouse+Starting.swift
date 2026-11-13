import Foundation

/// A house as the starting point of a Space made before Ode's presets: the
/// stored look recorded the house it began from.
extension SpaceHouse {
    /// The house a Space's look started from, by the name it recorded. Earlier
    /// builds recorded the house's English title, which differs only in case.
    static func startingPoint(of branding: SpaceBranding) -> SpaceHouse? {
        guard let recorded = branding.emblem.startingPresetID else { return nil }
        return all.first { $0.name.caseInsensitiveCompare(recorded) == .orderedSame }
    }

    /// The color preset that stands for this house: the one nearest its most
    /// colorful color.
    var preset: SpaceColorPreset {
        SpaceColorPreset.nearest(to: look.colorInputs)
    }
}
