import SwiftUI

/// A Boost's colors: dark pages, a tint in one of the Space colors and how
/// strong it is, and the page's brightness and contrast.
struct BrowserBoostColorsPanel: View {
    let boost: BrowserBoostSession

    /// The tint a swatch starts at, strong enough to see.
    private static let startingStrength = 0.35
    /// The Space colors a tint can take; the neutral ones would only dim.
    private static let tints = SpaceColorPreset.all.filter { $0.inputs.vividness >= 1 }

    var body: some View {
        if let shown = boost.draft {
            VStack(alignment: .leading, spacing: OdeSpacing.medium) {
                HStack {
                    Text("Dark")
                    Spacer(minLength: OdeSpacing.small)
                    Toggle(isOn: binding(\.isDark, in: shown)) {
                        Text("Dark")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityIdentifier("boost-dark")
                }
                VStack(alignment: .leading, spacing: OdeSpacing.small) {
                    HStack {
                        Text("Tint")
                        Spacer()
                        if shown.tintStrength > 0 {
                            Text(shown.tintStrength, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.panelDetail)
                        }
                    }
                    swatches(shown)
                    Slider(
                        value: Binding(
                            get: { max(shown.tintStrength, 0.1) },
                            set: { strength in boost.change { $0.tintStrength = strength } }), in: 0.1...1
                    ) {
                        Text("Tint strength")
                    }
                    .labelsHidden()
                    .disabled(shown.tintStrength == 0)
                    .accessibilityLabel("Tint strength")
                }
                level("Brightness", \.brightness, in: shown)
                level("Contrast", \.contrast, in: shown)
                Button("Reset Colors") {
                    boost.change {
                        $0.isDark = false
                        $0.tintStrength = 0
                        $0.brightness = 1
                        $0.contrast = 1
                    }
                }
                .buttonStyle(.odeTertiary)
                .disabled(!shown.isDark && shown.tintStrength == 0 && shown.brightness == 1 && shown.contrast == 1)
            }
            .padding(OdeSpacing.large)
            .frame(width: 300)
        }
    }

    private func swatches(_ shown: SiteBoost) -> some View {
        HStack(spacing: 6) {
            swatch(
                isSelected: shown.tintStrength == 0, label: Text("No Tint"),
                fill: AnyShapeStyle(.quaternary)
            ) {
                boost.change { $0.tintStrength = 0 }
            }
            .overlay {
                Image(systemName: "slash.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
            ForEach(Self.tints, id: \.name) { preset in
                swatch(
                    isSelected: shown.tintStrength > 0 && abs(shown.tintHue - preset.inputs.hue) < 0.5,
                    label: Text(preset.title), fill: AnyShapeStyle(preset.swatch.color)
                ) {
                    boost.change {
                        $0.tintHue = preset.inputs.hue
                        if $0.tintStrength == 0 { $0.tintStrength = Self.startingStrength }
                    }
                }
            }
        }
    }

    private func swatch(
        isSelected: Bool, label: Text, fill: AnyShapeStyle, action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 18, height: 18)
                .padding(2)
                .overlay {
                    Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(label)
    }

    private func level(
        _ title: LocalizedStringKey, _ keyPath: WritableKeyPath<SiteBoost, Double>, in shown: SiteBoost
    ) -> some View {
        VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
            HStack {
                Text(title)
                Spacer()
                Text(shown[keyPath: keyPath], format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.panelDetail)
            }
            Slider(
                value: Binding(
                    get: { shown[keyPath: keyPath] },
                    set: { value in boost.change { $0[keyPath: keyPath] = (value * 20).rounded() / 20 } }),
                in: SiteBoost.minimumLevel...SiteBoost.maximumLevel
            ) {
                Text(title)
            }
            .labelsHidden()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SiteBoost, Bool>, in shown: SiteBoost) -> Binding<Bool> {
        Binding(get: { shown[keyPath: keyPath] }, set: { value in boost.change { $0[keyPath: keyPath] = value } })
    }
}
