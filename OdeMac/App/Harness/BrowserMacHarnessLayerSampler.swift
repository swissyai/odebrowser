#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import IOSurface
    import QuartzCore

    /// Reads what a page's layers show at a point straight from the surfaces
    /// the engines hand Core Animation, which drawing the layers again into a
    /// bitmap would copy whole at every frame.
    ///
    /// It composites a layer's background, its contents and its sublayers,
    /// each at its opacity, as the window server does for the plain layers
    /// pages use. A point whose contents it cannot read reports so, and the
    /// sampler draws that frame the slow way instead.
    @MainActor
    struct BrowserMacHarnessLayerSampler {
        // MARK: - Types

        /// A premultiplied color, each channel from 0 to 1, and whether every
        /// layer at the point could be read.
        struct Sample {
            var color = SIMD4<Double>(0, 0, 0, 0)
            var isComplete = true
        }

        /// Why the last point that could not be read could not, for a run's
        /// record.
        static var lastFailure: String?

        // MARK: - Static Variables

        private typealias SurfaceGetter = @convention(c) (AnyObject) -> Unmanaged<IOSurfaceRef>?
        private typealias TypeIDGetter = @convention(c) () -> CFTypeID
        /// The type of Core Animation's own surface wrapper.
        private static let wrappedSurfaceType: CFTypeID? = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2), "CAIOSurfaceGetTypeID"
        ).map { unsafeBitCast($0, to: TypeIDGetter.self)() }
        /// WebKit hands Core Animation its tiles wrapped in Core Animation's
        /// own surface type, which only this function unwraps.
        private static let wrappedSurface: SurfaceGetter? = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2), "CAIOSurfaceGetIOSurface"
        ).map { unsafeBitCast($0, to: SurfaceGetter.self) }

        // MARK: - Variables

        /// Images already read, by identity, each drawn once into a small bitmap.
        private var images: [ObjectIdentifier: (bitmap: [UInt8], width: Int, height: Int)] = [:]

        // MARK: - Actions - Sampling

        /// What `layer` and the layers above it inside it show at `point`, in
        /// its own coordinates.
        mutating func sample(_ layer: CALayer, at point: CGPoint) -> Sample {
            guard !layer.isHidden, layer.opacity > 0 else { return Sample() }
            let inside = layer.bounds.contains(point)
            if layer.masksToBounds, !inside { return Sample() }
            var result = Sample()
            if inside, let background = layer.backgroundColor {
                result.color = Self.premultiplied(background)
            }
            if inside, let contents = layer.contents {
                if let pixel = pixel(of: contents as AnyObject, in: layer, at: point) {
                    result.color = Self.over(pixel, result.color)
                } else {
                    result.isComplete = false
                    Self.lastFailure = Self.describe(contents as AnyObject)
                }
            }
            let sublayers = (layer.sublayers ?? []).enumerated().sorted {
                $0.element.zPosition == $1.element.zPosition
                    ? $0.offset < $1.offset : $0.element.zPosition < $1.element.zPosition
            }
            for (_, sublayer) in sublayers {
                let above = sample(sublayer, at: sublayer.convert(point, from: layer))
                result.color = Self.over(above.color, result.color)
                result.isComplete = result.isComplete && above.isComplete
            }
            result.color *= Double(layer.opacity)
            return result
        }

        /// The pixel `contents` shows at `point` of `layer`, or nil when its
        /// kind of contents cannot be read.
        private mutating func pixel(of contents: AnyObject, in layer: CALayer, at point: CGPoint) -> SIMD4<Double>? {
            let bounds = layer.bounds
            guard bounds.width > 0, bounds.height > 0 else { return SIMD4(0, 0, 0, 0) }
            let rect = layer.contentsRect
            let u = (point.x - bounds.minX) / bounds.width
            let fromBottom = (point.y - bounds.minY) / bounds.height
            let fromTop = layer.contentsAreFlipped() ? fromBottom : 1 - fromBottom
            let x = rect.minX + u * rect.width
            let y = rect.minY + fromTop * rect.height
            let type = CFGetTypeID(contents as CFTypeRef)
            if type == IOSurfaceGetTypeID() {
                return Self.pixel(of: unsafeBitCast(contents, to: IOSurfaceRef.self), x: x, y: y)
            }
            if type == CGImage.typeID {
                return pixel(of: unsafeBitCast(contents, to: CGImage.self), x: x, y: y)
            }
            guard type == Self.wrappedSurfaceType, let surface = Self.wrappedSurface?(contents)?.takeUnretainedValue()
            else { return nil }
            return Self.pixel(of: surface, x: x, y: y)
        }

        /// The pixel at `x`, `y`, from 0 to 1 from the top left, of a surface
        /// in one of the formats Core Animation draws pages from.
        private static func pixel(of surface: IOSurfaceRef, x: Double, y: Double) -> SIMD4<Double>? {
            let width = IOSurfaceGetWidth(surface)
            let height = IOSurfaceGetHeight(surface)
            guard width > 0, height > 0 else { return nil }
            _ = IOSurfaceLock(surface, .readOnly, nil)
            defer { _ = IOSurfaceUnlock(surface, .readOnly, nil) }
            let column = min(width - 1, max(0, Int(x * Double(width))))
            let row = min(height - 1, max(0, Int(y * Double(height))))
            let base = IOSurfaceGetBaseAddress(surface)
            let rowStart = base + row * IOSurfaceGetBytesPerRow(surface)
            switch IOSurfaceGetPixelFormat(surface) {
            case 0x4247_5241:  // 'BGRA'
                let bytes = (rowStart + column * 4).assumingMemoryBound(to: UInt8.self)
                return SIMD4(Double(bytes[2]), Double(bytes[1]), Double(bytes[0]), Double(bytes[3])) / 255
            case 0x5247_4241:  // 'RGBA'
                let bytes = (rowStart + column * 4).assumingMemoryBound(to: UInt8.self)
                return SIMD4(Double(bytes[0]), Double(bytes[1]), Double(bytes[2]), Double(bytes[3])) / 255
            case 0x5247_6841:  // 'RGhA'
                let halves = (rowStart + column * 8).assumingMemoryBound(to: Float16.self)
                return SIMD4(Double(halves[0]), Double(halves[1]), Double(halves[2]), Double(halves[3]))
            case 0x6C31_3072:  // 'l10r'
                let word = (rowStart + column * 4).assumingMemoryBound(to: UInt32.self).pointee
                let channel = { (shift: UInt32) in Double((word >> shift) & 0x3FF) / 1023 }
                return SIMD4(channel(20), channel(10), channel(0), Double(word >> 30) / 3)
            default:
                return nil
            }
        }

        private mutating func pixel(of image: CGImage, x: Double, y: Double) -> SIMD4<Double>? {
            let key = ObjectIdentifier(image)
            if images[key] == nil {
                let width = min(64, max(1, image.width))
                let height = min(64, max(1, image.height))
                var bitmap = [UInt8](repeating: 0, count: width * height * 4)
                let drawn = bitmap.withUnsafeMutableBytes { buffer -> Bool in
                    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                        let context = CGContext(
                            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    return true
                }
                guard drawn else { return nil }
                images[key] = (bitmap, width, height)
            }
            guard let cached = images[key] else { return nil }
            let column = min(cached.width - 1, max(0, Int(x * Double(cached.width))))
            let row = min(cached.height - 1, max(0, Int(y * Double(cached.height))))
            let index = (row * cached.width + column) * 4
            return SIMD4(
                Double(cached.bitmap[index]), Double(cached.bitmap[index + 1]), Double(cached.bitmap[index + 2]),
                Double(cached.bitmap[index + 3])) / 255
        }

        /// What decides how `layer` and the layers in it look, short of their
        /// pixels: which layers, their geometry, opacity and background, and
        /// which contents each holds. An engine swaps in new contents for each
        /// frame it draws, so a frame whose signature matches the last one's
        /// shows the same pixels.
        static func signature(of layer: CALayer) -> Int {
            var hasher = Hasher()
            func add(_ layer: CALayer) {
                hasher.combine(ObjectIdentifier(layer))
                hasher.combine(layer.isHidden)
                hasher.combine(layer.opacity)
                hasher.combine(layer.frame.origin.x)
                hasher.combine(layer.frame.origin.y)
                hasher.combine(layer.bounds.width)
                hasher.combine(layer.bounds.height)
                hasher.combine(layer.backgroundColor.map { $0.components ?? [] } ?? [])
                if let contents = layer.contents { hasher.combine(ObjectIdentifier(contents as AnyObject)) }
                hasher.combine(layer.sublayers?.count ?? 0)
                for sublayer in layer.sublayers ?? [] { add(sublayer) }
            }
            add(layer)
            return hasher.finalize()
        }

        private static func describe(_ contents: AnyObject) -> String {
            let type = CFGetTypeID(contents as CFTypeRef)
            var text = String(describing: Swift.type(of: contents))
            var surface: IOSurfaceRef?
            if type == IOSurfaceGetTypeID() {
                text = "IOSurface"
                surface = unsafeBitCast(contents, to: IOSurfaceRef.self)
            } else if type == wrappedSurfaceType {
                text = "CAIOSurface"
                surface = wrappedSurface?(contents)?.takeUnretainedValue()
            }
            if let surface {
                let format = IOSurfaceGetPixelFormat(surface)
                let code = [24, 16, 8, 0].map { String(UnicodeScalar(UInt8((format >> $0) & 0xFF))) }.joined()
                text += " \(IOSurfaceGetWidth(surface))x\(IOSurfaceGetHeight(surface)) '\(code)'"
            }
            return text
        }

        private static func premultiplied(_ color: CGColor) -> SIMD4<Double> {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
                let components = converted.components, components.count >= 4
            else { return SIMD4(0, 0, 0, 0) }
            let alpha = Double(components[3])
            return SIMD4(
                Double(components[0]) * alpha, Double(components[1]) * alpha, Double(components[2]) * alpha, alpha)
        }

        /// `top` drawn over `bottom`, both premultiplied.
        private static func over(_ top: SIMD4<Double>, _ bottom: SIMD4<Double>) -> SIMD4<Double> {
            top + bottom * (1 - top.w)
        }
    }

#endif
