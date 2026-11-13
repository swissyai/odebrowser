import SwiftUI

/// One layer above the sidebar's base UI: the device's surface material in
/// `shape`, with an accent tint and a hover tint laid over it.
struct OdeSurfaceLayer<LayerShape: Shape>: View {
    let shape: LayerShape
    var tint: Color? = nil
    var hoverTint: Color? = nil

    @Environment(\.odeSurfaceMaterial) private var materialOverride

    var body: some View {
        shape
            .fill(OdeSurfaceMaterial.shown(materialOverride).material)
            .overlay {
                if let tint { shape.fill(tint) }
            }
            .overlay {
                if let hoverTint { shape.fill(hoverTint) }
            }
    }
}

#if DEBUG
    #Preview("Surface materials") {
        HStack(spacing: OdeSpacing.small) {
            ForEach(OdeSurfaceMaterial.all, id: \.self) { surface in
                Text(surface.title)
                    .font(.caption)
                    .padding(OdeSpacing.small)
                    .background { OdeSurfaceLayer(shape: .rect(cornerRadius: OdeRadius.compact)) }
                    .environment(\.odeSurfaceMaterial, surface)
            }
        }
        .padding()
        .background(.indigo.gradient)
    }
#endif
