import Foundation

enum BrowserSpaceBrandingPreviewFixture {
    /// The Azure preset as a solid tint.
    static let bannerBranding = SpaceColorPreset.azure.branding

    /// Three colors as gradient lights, with grain.
    static let gradientBranding: SpaceBranding = {
        var look = SpaceColorPreset.azure.branding
        look.colors = ColorPalette(
            colors: [SpaceColorPreset.azure.swatch, SpaceColorPreset.pink.swatch, SpaceColorPreset.yellow.swatch])
        look.themeMode = .gradient
        look.gradientAngle = 127
        look.showsTexture = true
        return look
    }()

    /// The Orange preset, worn by a guarded Space.
    static let guardedBranding = SpaceColorPreset.orange.branding

    /// A Space wearing the solid look, as the core resolves it.
    @MainActor static let simpleSpace = makeSpace(
        idByte: 0x11,
        profileByte: 0x21,
        name: "Winter",
        symbol: "snowflake",
        accent: .indigo,
        branding: bannerBranding,
        accessPolicy: .open
    )

    /// A guarded Space, as the core resolves it.
    @MainActor static let guardedSpace = makeSpace(
        idByte: 0x12,
        profileByte: 0x22,
        name: "Studio",
        symbol: "paintpalette.fill",
        accent: .orange,
        branding: guardedBranding,
        accessPolicy: .deviceOwnerAuthentication
    )

    @MainActor
    private static func makeSpace(
        idByte: UInt8,
        profileByte: UInt8,
        name: String,
        symbol: String,
        accent: SpaceAccent,
        branding: SpaceBranding,
        accessPolicy: SpaceAccessPolicy
    ) -> SpaceModel {
        SpaceModel.detached(
            SpaceState.Seed(
                id: deterministicUUID(finalByte: idByte), profileID: deterministicUUID(finalByte: profileByte),
                name: name, symbol: symbol, accent: accent, branding: branding, tabs: [],
                accessPolicy: accessPolicy))
    }

    private static func deterministicUUID(finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x50, 0x41,
                0x43, 0x45,
                0x42, 0x52, 0x41, 0x4E, 0x44, finalByte
            ))
    }
}
