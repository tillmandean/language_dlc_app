import CoreGraphics
import Foundation

/// Draws the equirectangular world map twice:
///  - `renderTexture` produces the visible, colored image wrapped onto the globe.
///  - the pick map is an invisible index image kept in memory, used to answer
///    "which country is at this texture coordinate?" with a single pixel read.
///
/// Projection (image top-left is 180°W, 90°N):
///     x = (lon + 180) / 360 * width
///     y = (90 - lat)  / 180 * height
final class MapRasterizer {

    /// Built lazily on first use, off whichever thread touches it first.
    static let shared = MapRasterizer(countries: DataStore.shared.countries,
                                      regions: DataStore.shared.regions)

    /// The one place to shrink the texture (e.g. to 2048x1024) if memory warnings show up on
    /// older devices — everything else derives from these two numbers.
    static let defaultWidth = 4096
    static let defaultHeight = 2048

    let width: Int
    let height: Int
    /// The pick map is half resolution: plenty for tap accuracy, a quarter of the memory.
    let pickWidth: Int
    let pickHeight: Int

    private(set) var ids: [String] = []          // index -> territory code
    /// Curated sub-national regions (Phase 10.4), drawn on top of the country fill — in the pick
    /// map as well as the visible texture, so a tap inside one resolves to the region.
    private(set) var regionIds: [String] = []
    /// Parallel to `regionIds`: the alpha-2 country each region belongs to, so a region hit can
    /// name its parent without re-parsing the id.
    private(set) var regionCountries: [String] = []

    private struct Shape {
        let path: CGPath      // three copies (-width, 0, +width), texture pixel space
        let bounds: CGRect    // bounds of the un-offset copy only
        let label: CGPoint    // labelLon/labelLat in texture pixel space
    }
    private var shapes: [Shape] = []             // parallel to ids
    private var regionShapes: [Shape] = []       // parallel to regionIds
    private var pickBuffer: [UInt8] = []         // RGBA, pickWidth * pickHeight * 4

    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(countries: [CountryGeometry], regions: [RegionGeometry] = [],
        width: Int = MapRasterizer.defaultWidth, height: Int = MapRasterizer.defaultHeight) {
        self.width = width
        self.height = height
        self.pickWidth = max(1, width / 2)
        self.pickHeight = max(1, height / 2)

        for country in countries {
            guard let shape = Self.makeShape(rings: country.rings, labelLon: country.labelLon,
                                             labelLat: country.labelLat, width: width, height: height)
            else { continue }
            ids.append(country.id)
            shapes.append(shape)
        }
        for region in regions {
            guard let shape = Self.makeShape(rings: region.rings, labelLon: region.labelLon,
                                             labelLat: region.labelLat, width: width, height: height)
            else { continue }
            regionIds.append(region.id)
            regionCountries.append(region.country)
            regionShapes.append(shape)
        }
        renderPickMap()
    }

    // MARK: - Geometry

    /// Projects every ring into pixel space, unwrapping longitudes across the antimeridian and
    /// emitting three copies of the result so the wrapped parts land back on the canvas. Shared
    /// by countries and curated regions — both are just a set of rings plus a label point.
    private static func makeShape(rings: [[Double]], labelLon: Double, labelLat: Double,
                                  width: Int, height: Int) -> Shape? {
        let w = CGFloat(width), h = CGFloat(height)
        let base = CGMutablePath()
        var hasRing = false

        for ring in rings {
            guard ring.count >= 6 else { continue }        // needs 3+ points
            var previousLon = ring[0]
            var running = ring[0]
            var points: [CGPoint] = []
            points.reserveCapacity(ring.count / 2)

            var i = 0
            while i + 1 < ring.count {
                let lon = ring[i], lat = ring[i + 1]
                if i == 0 {
                    running = lon
                } else {
                    // Keep the running longitude continuous: a jump of more than 180° is a
                    // wrap, not real movement.
                    var delta = lon - previousLon
                    while delta > 180 { delta -= 360 }
                    while delta < -180 { delta += 360 }
                    running += delta
                }
                previousLon = lon
                points.append(CGPoint(x: (CGFloat(running) + 180) / 360 * w,
                                      y: (90 - CGFloat(lat)) / 180 * h))
                i += 2
            }

            guard points.count >= 3 else { continue }
            base.move(to: points[0])
            base.addLines(between: Array(points.dropFirst()))
            base.closeSubpath()
            hasRing = true
        }

        guard hasRing else { return nil }
        let bounds = base.boundingBoxOfPath

        let full = CGMutablePath()
        for dx in [-w, 0, w] {
            full.addPath(base, transform: CGAffineTransform(translationX: dx, y: 0))
        }

        let label = CGPoint(x: (CGFloat(labelLon) + 180) / 360 * w,
                            y: (90 - CGFloat(labelLat)) / 180 * h)
        return Shape(path: full, bounds: bounds, label: label)
    }

    // MARK: - Visible texture

    /// Draws the visible globe texture. Cached paths make this a fill pass, not a re-parse.
    /// `regionColors` is looked up by curated region id (Phase 10.4) — a region with no entry is
    /// left undrawn entirely, so the country's own fill underneath keeps showing through.
    func renderTexture(colors: [String: CGColor],
                       ocean: CGColor,
                       lockedLand: CGColor,
                       borders: CGColor,
                       regionColors: [String: CGColor] = [:]) -> CGImage? {
        guard let ctx = makeContext(width: width, height: height) else { return nil }
        ctx.setFillColor(ocean)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (i, shape) in shapes.enumerated() {
            ctx.setFillColor(colors[ids[i]] ?? lockedLand)
            ctx.addPath(shape.path)
            ctx.fillPath(using: .evenOdd)   // holes and enclaves
        }
        // Second pass: a bigger neighbour drawn later must not bury a city-state's dot.
        for (i, shape) in shapes.enumerated() where isTiny(shape, scale: 1) {
            ctx.setFillColor(colors[ids[i]] ?? lockedLand)
            drawDot(shape, in: ctx, scale: 1)
        }

        ctx.setStrokeColor(borders)
        ctx.setLineWidth(1)
        ctx.setLineJoin(.round)
        for shape in shapes {
            ctx.addPath(shape.path)
            ctx.strokePath()
        }

        if !regionColors.isEmpty {
            for (i, shape) in regionShapes.enumerated() {
                guard let color = regionColors[regionIds[i]] else { continue }
                ctx.setFillColor(color)
                ctx.addPath(shape.path)
                ctx.fillPath(using: .evenOdd)
            }
            ctx.setStrokeColor(borders)
            ctx.setLineWidth(0.5)
            ctx.setLineJoin(.round)
            for (i, shape) in regionShapes.enumerated() where regionColors[regionIds[i]] != nil {
                ctx.addPath(shape.path)
                ctx.strokePath()
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Pick map

    /// Draws the invisible index map. Called once from `init`; the result lives in `pickBuffer`.
    private func renderPickMap() {
        guard let ctx = makeContext(width: pickWidth, height: pickHeight) else { return }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        // Index 0 is ocean.
        ctx.setFillColor(Self.indexColor(0))
        ctx.fill(CGRect(x: 0, y: 0, width: pickWidth, height: pickHeight))

        // Draw in texture pixel space; the context scales down to pick resolution.
        let scale = CGFloat(pickWidth) / CGFloat(width)
        ctx.scaleBy(x: scale, y: scale)

        for (i, shape) in shapes.enumerated() {
            ctx.setFillColor(Self.indexColor(i + 1))
            ctx.addPath(shape.path)
            ctx.fillPath(using: .evenOdd)
        }
        for (i, shape) in shapes.enumerated() where isTiny(shape, scale: scale) {
            ctx.setFillColor(Self.indexColor(i + 1))
            drawDot(shape, in: ctx, scale: scale)
        }

        // Regions last, so they sit on top of the country they carve into — the same order the
        // visible texture draws them in, which is what keeps a tap agreeing with what's on screen.
        //
        // Deliberately no tiny-shape dots here. A country too small to rasterize still has to be
        // reachable somehow, so a dot is the only option; a canton too small to rasterize is
        // already invisible on the globe, and giving it a hit target the user cannot see would
        // steal taps from the country around it.
        for (i, shape) in regionShapes.enumerated() {
            ctx.setFillColor(Self.indexColor(ids.count + 1 + i))
            ctx.addPath(shape.path)
            ctx.fillPath(using: .evenOdd)
        }

        guard let data = ctx.data else { return }
        let count = pickWidth * pickHeight * 4
        pickBuffer = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                                 count: count))
    }

    /// Index 0 is ocean; every other index encodes as r = low byte, g = high byte.
    private static func indexColor(_ index: Int) -> CGColor {
        CGColor(colorSpace: colorSpace,
                components: [CGFloat(index & 0xFF) / 255,
                             CGFloat((index >> 8) & 0xFF) / 255,
                             0, 1])!
    }

    // MARK: - Hit testing

    /// `u`, `v` are texture coordinates in 0...1 with v measured from the top of the image.
    /// Returns nil only if nothing but ocean lies within `tolerancePixels` (pick-map pixels).
    func feature(atU u: Double, v: Double, tolerancePixels: Int = 12) -> MapFeature? {
        guard !pickBuffer.isEmpty else { return nil }
        let wrappedU = u - floor(u)
        let x = min(pickWidth - 1, max(0, Int(wrappedU * Double(pickWidth))))
        let y = min(pickHeight - 1, max(0, Int(min(max(v, 0), 1) * Double(pickHeight))))

        if let hit = feature(atX: x, y: y) { return hit }
        // Spiral outward so pinprick islands stay tappable.
        guard tolerancePixels > 0 else { return nil }
        for r in 1...tolerancePixels {
            for dx in -r...r {
                if let hit = feature(atX: x + dx, y: y - r) { return hit }
                if let hit = feature(atX: x + dx, y: y + r) { return hit }
            }
            if r > 1 {
                for dy in (-r + 1)...(r - 1) {
                    if let hit = feature(atX: x - r, y: y + dy) { return hit }
                    if let hit = feature(atX: x + r, y: y + dy) { return hit }
                }
            }
        }
        return nil
    }

    /// The same lookup reduced to a country code: a tap inside a curated region reports the
    /// country containing it. This is what callers that only deal in territories want, and it
    /// keeps the pick map's country-level behaviour identical to before regions were added to it.
    func territory(atU u: Double, v: Double, tolerancePixels: Int = 12) -> String? {
        feature(atU: u, v: v, tolerancePixels: tolerancePixels)?.territory
    }

    private func feature(atX x: Int, y: Int) -> MapFeature? {
        guard y >= 0, y < pickHeight else { return nil }
        let wrappedX = ((x % pickWidth) + pickWidth) % pickWidth   // the map is a cylinder
        let offset = (y * pickWidth + wrappedX) * 4
        let index = Int(pickBuffer[offset]) | (Int(pickBuffer[offset + 1]) << 8)
        guard index > 0 else { return nil }                        // 0 is ocean
        if index <= ids.count { return .country(ids[index - 1]) }
        let regionIndex = index - ids.count - 1
        guard regionIndex < regionIds.count else { return nil }
        return .region(id: regionIds[regionIndex], country: regionCountries[regionIndex])
    }

    // MARK: - Drawing helpers

    private func makeContext(width: Int, height: Int) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: Self.colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Top-left origin, so the projection formula can be used as written.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        return ctx
    }

    /// Singapore, Malta, Bahrain: too small to survive rasterization at either resolution.
    /// `scale` is the context's device-pixels-per-texture-pixel.
    private func isTiny(_ shape: Shape, scale: CGFloat) -> Bool {
        shape.bounds.width * scale < 3 || shape.bounds.height * scale < 3
    }

    /// Gives a country too small to draw a fixed 3 px dot, so it stays visible and tappable.
    private func drawDot(_ shape: Shape, in ctx: CGContext, scale: CGFloat) {
        let r: CGFloat = 3 / scale
        ctx.fillEllipse(in: CGRect(x: shape.label.x - r, y: shape.label.y - r,
                                   width: r * 2, height: r * 2))
    }
}

// MARK: - Calibration

extension MapRasterizer {

    /// A texture with no map on it, used once to pin down how `SCNSphere` orients its UVs
    /// (§5.1). Red dot at (0°, 0°), green at (0°, 90°E), blue at (0°, 90°W), white bar across
    /// the top 20 rows — so the bar marks the north pole and green sits east of red.
    func renderCalibrationTexture() -> CGImage? {
        guard let ctx = makeContext(width: width, height: height) else { return nil }
        ctx.setFillColor(Palette.ocean)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.setFillColor(CGColor(colorSpace: Self.colorSpace, components: [1, 1, 1, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: 20))

        func dot(lon: Double, lat: Double, _ components: [CGFloat]) {
            ctx.setFillColor(CGColor(colorSpace: Self.colorSpace, components: components)!)
            let c = point(lon: lon, lat: lat)
            ctx.fillEllipse(in: CGRect(x: c.x - 40, y: c.y - 40, width: 80, height: 80))
        }
        dot(lon: 0, lat: 0, [1, 0, 0, 1])
        dot(lon: 90, lat: 0, [0, 1, 0, 1])
        dot(lon: -90, lat: 0, [0, 0, 1, 1])

        return ctx.makeImage()
    }

    /// (lon, lat) in degrees -> texture pixel space, §4.1.
    func point(lon: Double, lat: Double) -> CGPoint {
        CGPoint(x: (CGFloat(lon) + 180) / 360 * CGFloat(width),
                y: (90 - CGFloat(lat)) / 180 * CGFloat(height))
    }
}
