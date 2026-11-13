// Writes the layers of Ode.icon from the same paths the app draws its mark
// with, so the icon's fold and the app's are one curve. The counter stays
// negative space: as its own glass layer it reads as a button in the O.
// Compile it together with the app's geometry:
//
//   swiftc -O -parse-as-library OdeShared/DesignSystem/Components/OdeMark/OdeMarkGeometry.swift \
//     tools/dev/generate-mark.swift -o "$TMPDIR/generate-mark"
//   "$TMPDIR/generate-mark" OdeShared/Resources/OdeIcon/Ode.icon/Assets \
//     --logo HelpCenter/static/img/ode-logo.svg [--png <folder>]
//
// `--logo` writes the mark on its tile as one SVG for web pages; `--png`
// renders the flat mark at the icon's sizes, for review.
import AppKit
import CoreGraphics

struct Layer {
    let file: String
    let path: CGPath?
    let fill: String
}

func svgData(_ path: CGPath) -> String {
    var parts: [String] = []
    func point(_ p: CGPoint) -> String { String(format: "%.2f %.2f", p.x, p.y) }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: parts.append("M" + point(points[0]))
        case .addLineToPoint: parts.append("L" + point(points[0]))
        case .addQuadCurveToPoint: parts.append("Q" + point(points[0]) + " " + point(points[1]))
        case .addCurveToPoint:
            parts.append("C" + point(points[0]) + " " + point(points[1]) + " " + point(points[2]))
        case .closeSubpath: parts.append("Z")
        @unknown default: break
        }
    }
    return parts.joined(separator: " ")
}

func svg(_ layer: Layer) -> String {
    let body: String
    if let path = layer.path {
        body = "  <path fill=\"\(layer.fill)\" fill-rule=\"evenodd\" d=\"\(svgData(path))\"/>"
    } else {
        body = "  <rect width=\"1024\" height=\"1024\" fill=\"\(layer.fill)\"/>"
    }
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
        \(body)
        </svg>

        """
}

@MainActor let layers = [
    Layer(file: "OdeBackground.svg", path: nil, fill: "#F6F5F0"),
    Layer(file: "OdeDarkBackground.svg", path: nil, fill: "#151516"),
    Layer(file: "OdeRing.svg", path: OdeMarkGeometry.ring, fill: "#3050F0"),
    Layer(file: "OdeDarkRing.svg", path: OdeMarkGeometry.ring, fill: "#6E8BFF"),
    Layer(file: "OdeTintedRing.svg", path: OdeMarkGeometry.ring, fill: "#FFFFFF"),
    Layer(file: "OdeFlap.svg", path: OdeMarkGeometry.flap, fill: "#F07A70"),
    Layer(file: "OdeTintedFlap.svg", path: OdeMarkGeometry.flap, fill: "#FFFFFF"),
]

@main
@MainActor
enum GenerateMark {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(
                "Usage: generate-mark <Ode.icon/Assets> [--logo <file.svg>] [--png <folder>]\n".data(using: .utf8)!)
            exit(64)
        }
        func option(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let assets = URL(fileURLWithPath: arguments[1], isDirectory: true)
        for layer in layers {
            try svg(layer).write(to: assets.appendingPathComponent(layer.file), atomically: true, encoding: .utf8)
        }
        print("Wrote \(layers.count) layers to \(assets.path)")

        if let logo = option("--logo") {
            let mark = """
                <?xml version="1.0" encoding="UTF-8"?>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title">
                  <title id="title">Ode</title>
                  <rect x="40" y="40" width="944" height="944" rx="224" fill="#F6F5F0"/>
                  <path fill="#F07A70" fill-rule="evenodd" d="\(svgData(OdeMarkGeometry.flap))"/>
                  <path fill="#3050F0" fill-rule="evenodd" d="\(svgData(OdeMarkGeometry.ring))"/>
                  <rect x="40.5" y="40.5" width="943" height="943" rx="223.5" fill="none" stroke="#172238" stroke-opacity=".1"/>
                </svg>

                """
            try mark.write(toFile: logo, atomically: true, encoding: .utf8)
            print("Wrote \(logo)")
        }

        if let png = option("--png") {
            let folder = URL(fileURLWithPath: png, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, dark) in [("light", false), ("dark", true)] {
                for side in [1024, 128, 32, 16] {
                    let small = CGFloat(side) <= OdeMarkGeometry.smallSide
                    let context = CGContext(
                        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.setFillColor(
                        dark
                            ? CGColor(srgbRed: 0.082, green: 0.082, blue: 0.086, alpha: 1)
                            : CGColor(srgbRed: 0.965, green: 0.961, blue: 0.941, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                    // CoreGraphics is y-up; the canvas is y-down.
                    let scale = CGFloat(side) / OdeMarkGeometry.canvas
                    context.translateBy(x: 0, y: CGFloat(side))
                    context.scaleBy(x: scale, y: -scale)
                    context.addPath(small ? OdeMarkGeometry.smallFlap : OdeMarkGeometry.flap)
                    context.setFillColor(CGColor(srgbRed: 240 / 255, green: 122 / 255, blue: 112 / 255, alpha: 1))
                    context.fillPath(using: .evenOdd)
                    context.addPath(small ? OdeMarkGeometry.smallRing : OdeMarkGeometry.ring)
                    context.setFillColor(
                        dark
                            ? CGColor(srgbRed: 110 / 255, green: 139 / 255, blue: 1, alpha: 1)
                            : CGColor(srgbRed: 48 / 255, green: 80 / 255, blue: 240 / 255, alpha: 1))
                    context.fillPath(using: .evenOdd)
                    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
                    try image.representation(using: .png, properties: [:])!
                        .write(to: folder.appendingPathComponent("mark-\(name)-\(side).png"))
                }
            }
            print("Rendered the mark to \(folder.path)")
        }
    }
}
