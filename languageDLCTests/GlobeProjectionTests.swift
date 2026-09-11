import Testing
import SceneKit
import UIKit
@testable import languageDLC

/// §5.1 calibration, done against the real `SCNSphere` instead of by eye: these tests read the
/// sphere's own UV source, render it offscreen, and hit-test it. If SceneKit ever changes how
/// it orients texture coordinates, `GlobeProjection`'s flags stop matching and these fail.
@MainActor
@Suite(.serialized)   // each test drives its own SCNView; SceneKit dislikes concurrent renderers
struct GlobeProjectionTests {

    private static let size = CGSize(width: 400, height: 400)

    private func makeView(texture: CGImage?) -> SCNView {
        let built = GlobeView.makeScene()
        let view = SCNView(frame: CGRect(origin: .zero, size: Self.size))
        view.scene = built.scene
        view.pointOfView = built.camera
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = false
        if let texture {
            built.globe.geometry?.firstMaterial?.diffuse.contents = texture
        }
        return view
    }

    // MARK: - Geometry sources

    private struct Vertex { let position: SCNVector3; let uv: CGPoint }

    private func vertices(of geometry: SCNGeometry) -> [Vertex] {
        guard let positions = geometry.sources(for: .vertex).first,
              let texcoords = geometry.sources(for: .texcoord).first else { return [] }
        let p = read(positions) { SCNVector3(Float($0[0]), Float($0[1]), Float($0[2])) }
        let t = read(texcoords) { CGPoint(x: CGFloat($0[0]), y: CGFloat($0[1])) }
        return zip(p, t).map(Vertex.init)
    }

    /// Walks a geometry source honoring its stride and offset, handing each element's
    /// components to `make` as Floats.
    private func read<T>(_ source: SCNGeometrySource, _ make: ([Float]) -> T) -> [T] {
        var out: [T] = []
        out.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { raw in
            for i in 0..<source.vectorCount {
                let base = source.dataOffset + i * source.dataStride
                var components: [Float] = []
                for c in 0..<source.componentsPerVector {
                    let offset = base + c * source.bytesPerComponent
                    components.append(source.bytesPerComponent == 8
                                      ? Float(raw.loadUnaligned(fromByteOffset: offset, as: Double.self))
                                      : raw.loadUnaligned(fromByteOffset: offset, as: Float.self))
                }
                out.append(make(components))
            }
        }
        return out
    }

    private func globeNode(_ view: SCNView) -> SCNNode? {
        view.scene?.rootNode.childNode(withName: GlobeView.globeNodeName, recursively: false)
    }

    /// The sphere vertex whose texture coordinate is closest to the one we want.
    private func nearestVertex(_ view: SCNView, u: Double, v: Double) -> Vertex? {
        guard let geometry = globeNode(view)?.geometry else { return nil }
        let target = GlobeProjection.encode(u: u, v: v)
        return vertices(of: geometry).min { distance($0.uv, target) < distance($1.uv, target) }
    }

    /// Spins the globe about its axis until `position` faces the camera, and returns where that
    /// point now lands on screen.
    private func bringToFront(_ view: SCNView, _ position: SCNVector3) -> CGPoint? {
        guard let globe = globeNode(view) else { return nil }
        let azimuth = atan2(Double(position.x), Double(position.z))
        globe.eulerAngles = SCNVector3(0, Float(-azimuth), 0)
        _ = view.snapshot()   // hit testing reads presentation values, which only a render syncs
        let screen = view.projectPoint(globe.convertPosition(position, to: nil))
        return CGPoint(x: CGFloat(screen.x), y: CGFloat(screen.y))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        var dx = abs(a.x - b.x)
        if dx > 0.5 { dx = 1 - dx }                       // u wraps
        return dx * dx + (a.y - b.y) * (a.y - b.y)
    }

    private func tap(_ view: SCNView, at point: CGPoint) -> (u: Double, v: Double)? {
        GlobeView.textureCoordinate(in: view, at: point)
    }

    // MARK: - §5.1 steps 3 and 4

    /// Step 3: the top of the texture must render at the top of the globe. The probe is a
    /// two-tone image — white where the map draws the northern hemisphere — so a correct
    /// sphere is white above its equator and dark below it. If this fails, `flipV` is wrong
    /// and the map is upside down.
    @Test func textureTopRendersAtTheNorthPole() throws {
        let view = makeView(texture: try #require(Self.hemisphereProbe()))
        let sampler = try #require(PixelSampler(view.snapshot()))
        let center = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        #expect(sampler.isWhite(x: Int(center.x), y: Int(center.y - 60)))
        #expect(!sampler.isWhite(x: Int(center.x), y: Int(center.y + 60)))
    }

    /// White over the northern half of an equirectangular map, black over the southern half.
    private static func hemisphereProbe() -> CGImage? {
        guard let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
                                  bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: 32)
        ctx.scaleBy(x: 1, y: -1)                          // top-left origin, as in MapRasterizer
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 16))   // 0°N ... 90°N
        return ctx.makeImage()
    }

    /// Step 4: dragging east must raise the texture's u — i.e. on the visible hemisphere,
    /// screen-right is east. If this fails, `mirrorU` is wrong.
    @Test func eastIsToTheRight() throws {
        let view = makeView(texture: nil)
        let center = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        let left = try #require(tap(view, at: CGPoint(x: center.x - 60, y: center.y)))
        let right = try #require(tap(view, at: CGPoint(x: center.x + 60, y: center.y)))
        var delta = right.u - left.u
        if delta < -0.5 { delta += 1 }                    // the seam may sit between them
        #expect(delta > 0)
    }

    /// Screen-up is north, which in the rasterizer's convention means a *smaller* v.
    @Test func upIsNorth() throws {
        let view = makeView(texture: nil)
        let center = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        let above = try #require(tap(view, at: CGPoint(x: center.x, y: center.y - 60)))
        let below = try #require(tap(view, at: CGPoint(x: center.x, y: center.y + 60)))
        #expect(above.v < below.v)
    }

    /// The calibration in one assertion: every vertex of the sphere carries the texture
    /// coordinate that the rasterizer's own projection would assign to its latitude and
    /// longitude. This is what lets `GlobeProjection`'s three corrections stay no-ops.
    @Test func sphereUnwrapsToTheRasterizersProjection() throws {
        let view = makeView(texture: nil)
        let geometry = try #require(globeNode(view)?.geometry)
        let sampled = vertices(of: geometry)
        #expect(sampled.count > 1000)

        for vertex in sampled {
            let p = vertex.position
            let lat = asin(min(max(Double(p.y), -1), 1)) * 180 / .pi
            let lon = atan2(Double(p.x), Double(p.z)) * 180 / .pi
            let expected = GlobeProjection.encode(u: (lon + 180) / 360, v: (90 - lat) / 180)
            // The poles and the seam are parameterised as whole edges, so only compare v there.
            #expect(abs(vertex.uv.y - expected.y) < 0.002)
            if abs(lat) < 89, abs(abs(lon) - 180) > 1 {
                #expect(abs(vertex.uv.x - expected.x) < 0.002)
            }
        }
    }

    /// The sphere's seam of triangles runs straight down the middle of the view, and SceneKit
    /// reports a miss for a ray that lands exactly on a shared edge. Taps there must still land.
    @Test func tapsOnTheCentreLineStillHit() throws {
        let view = makeView(texture: nil)
        let cx = Self.size.width / 2
        for y in stride(from: Self.size.height * 0.3, through: Self.size.height * 0.7, by: 20) {
            #expect(tap(view, at: CGPoint(x: cx, y: y)) != nil)
        }
    }

    // MARK: - §5.1 step 6

    /// Five known places, taken all the way through the real path: sphere UV -> screen point ->
    /// SceneKit hit test -> `GlobeProjection.decode` -> pick map.
    @Test func calibrationTapsResolve() throws {
        let places: [(expected: String, lon: Double, lat: Double)] = [
            ("BR", -47.93, -15.78),      // Brasilia
            ("AU", 133.0, -24.0),        // central Australia
            ("JP", 139.69, 35.68),       // Tokyo
            ("EG", 30.8, 26.8),          // central Egypt
            ("US", -150.0, 63.0),        // interior Alaska
        ]
        let view = makeView(texture: nil)
        for place in places {
            let u = (place.lon + 180) / 360
            let v = (90 - place.lat) / 180
            let vertex = try #require(nearestVertex(view, u: u, v: v))
            let point = try #require(bringToFront(view, vertex.position))
            let decoded = try #require(tap(view, at: point))
            #expect(MapRasterizer.shared.territory(atU: decoded.u, v: decoded.v) == place.expected)
        }
    }
}

/// The globe has to redraw every frame while the user drags it, so a frame must cost well
/// under the 16.6 ms that 60 fps allows — with the full 4096x2048 texture on it.
@MainActor
@Suite(.serialized)
struct GlobeRenderingTests {

    @Test func aFrameCostsFarLessThanASixtiethOfASecond() throws {
        let built = GlobeView.makeScene()
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        view.scene = built.scene
        view.pointOfView = built.camera
        built.globe.geometry?.firstMaterial?.diffuse.contents =
            try #require(MapRasterizer.shared.renderTexture(colors: [:],
                                                            ocean: Palette.ocean,
                                                            lockedLand: Palette.lockedLand,
                                                            borders: Palette.borders))
        _ = view.snapshot()                               // first frame uploads the texture

        let frames = 30
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<frames {
            built.globe.eulerAngles = SCNVector3(0, Float(i) * 0.05, 0)
            _ = view.snapshot()
        }
        let perFrame = (CFAbsoluteTimeGetCurrent() - start) / Double(frames)
        #expect(perFrame < 1.0 / 60)
    }
}

/// Minimal RGBA reader over a rendered `UIImage`.
private struct PixelSampler {
    let width: Int, height: Int
    let data: Data
    let bytesPerRow: Int

    init?(_ image: UIImage) {
        guard let cg = image.cgImage, let pixels = cg.dataProvider?.data as Data? else { return nil }
        width = cg.width
        height = cg.height
        bytesPerRow = cg.bytesPerRow
        data = pixels
    }

    /// `x`, `y` are in points of a 400 pt view; the snapshot is at screen scale.
    func isWhite(x: Int, y: Int, threshold: UInt8 = 200) -> Bool {
        let scale = width / 400
        let px = x * scale, py = y * scale
        guard px >= 0, px < width, py >= 0, py < height else { return false }
        let o = py * bytesPerRow + px * 4
        return data[o] > threshold && data[o + 1] > threshold && data[o + 2] > threshold
    }
}
