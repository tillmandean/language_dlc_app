import SwiftUI
import SceneKit

/// Where the texture's (u, v) sits on `SCNSphere`, calibrated once against the sphere's own
/// UV source (§5.1) rather than guessed.
///
/// Measured: `SCNSphere` unwraps to exactly the rasterizer's equirectangular projection —
/// v = 0 at the north pole, u = 0 at 180°W with u rising eastward, seam at the back — so all
/// three corrections are no-ops. `GlobeProjectionTests` re-derives this from the geometry on
/// every run, so a SceneKit change shows up as a failing test rather than a crooked map.
struct GlobeProjection {
    static var flipV = false     // true if v runs bottom-up on the sphere
    static var mirrorU = false   // true if u runs east-to-west
    static var uOffset = 0.0     // fine longitude shift, 0...1

    /// SceneKit texture coordinate -> the (u, v) the rasterizer's pick map expects.
    static func decode(_ tc: CGPoint) -> (u: Double, v: Double) {
        var u = Double(tc.x) - uOffset
        if mirrorU { u = 1 - u }
        u = u - floor(u)                       // wrap into 0...1
        let v = flipV ? 1 - Double(tc.y) : Double(tc.y)
        return (u, min(max(v, 0), 1))
    }

    /// Exact inverse of `decode`: the sphere texture coordinate that shows map point (u, v).
    static func encode(u: Double, v: Double) -> CGPoint {
        var x = mirrorU ? 1 - u : u
        x += uOffset
        x -= floor(x)
        return CGPoint(x: x, y: flipV ? 1 - v : v)
    }
}

/// A plain sphere with the world map painted on it. All the geography lives in the texture;
/// this view only has to spin it and turn a tap into a texture coordinate.
struct GlobeView: UIViewRepresentable {
    var texture: CGImage?
    /// Reports texture coordinates (u, v), each 0...1, already decoded through `GlobeProjection`.
    var onTap: (Double, Double) -> Void

    /// Seconds for one idle revolution; cancelled the moment the user touches the globe.
    private static let spinDuration: TimeInterval = 90

    func makeUIView(context: Context) -> SCNView {
        let view = TouchReportingSCNView()
        let built = Self.makeScene()
        view.scene = built.scene
        view.pointOfView = built.camera
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = true          // replaced with custom gestures in Phase 9
        view.autoenablesDefaultLighting = false
        view.isPlaying = true                    // actions only advance on a playing view

        let globe = built.globe
        globe.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0,
                                                 duration: Self.spinDuration)),
                        forKey: Self.spinActionKey)
        view.onFirstTouch = { [weak globe] in globe?.removeAction(forKey: Self.spinActionKey) }

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    /// Scene, sphere and camera, built in one place so `GlobeProjectionTests` calibrates
    /// against exactly the geometry the app ships.
    static func makeScene() -> (scene: SCNScene, globe: SCNNode, camera: SCNNode) {
        let scene = SCNScene()

        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 96                 // avoids visible faceting at the silhouette
        let material = sphere.firstMaterial!
        material.lightingModel = .constant       // texture colors render exactly as drawn
        material.diffuse.wrapS = .repeat
        material.diffuse.mipFilter = .linear
        material.isDoubleSided = false

        let globe = SCNNode(geometry: sphere)
        globe.name = globeNodeName
        scene.rootNode.addChildNode(globe)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        // On a portrait phone the default (vertical) reading of the field of view makes the
        // globe wider than the screen; measuring it across the width fits the sphere with a
        // margin at any aspect ratio.
        camera.camera?.projectionDirection = .horizontal
        camera.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(camera)

        return (scene, globe, camera)
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        guard let texture else { return }
        let node = view.scene?.rootNode.childNode(withName: Self.globeNodeName, recursively: false)
        // Any state change re-runs the body — a tapped country, say — and re-assigning the
        // contents would push the whole 4096x2048 image to the GPU again for nothing.
        guard context.coordinator.appliedTexture !== texture else { return }
        node?.geometry?.firstMaterial?.diffuse.contents = texture
        context.coordinator.appliedTexture = texture
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    static let globeNodeName = "globe"
    private static let spinActionKey = "idleSpin"

    /// The map coordinate under a point in the view, or nil if the tap missed the globe.
    ///
    /// SceneKit's ray test reports a miss when the ray lands exactly on a shared triangle edge,
    /// and the sphere's seam column runs straight down the middle of the view — so a tap on the
    /// exact centre line would otherwise do nothing. Half a point to the side is the whole fix.
    static func textureCoordinate(in view: SCNView, at point: CGPoint) -> (u: Double, v: Double)? {
        let options: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue
        ]
        let nudged = CGPoint(x: point.x + 0.5, y: point.y + 0.5)
        guard let hit = view.hitTest(point, options: options).first
                ?? view.hitTest(nudged, options: options).first
        else { return nil }
        return GlobeProjection.decode(hit.textureCoordinates(withMappingChannel: 0))
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        var onTap: (Double, Double) -> Void
        /// The image currently on the sphere, so a redundant update can skip the upload.
        var appliedTexture: CGImage?
        init(onTap: @escaping (Double, Double) -> Void) { self.onTap = onTap }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view,
                  let (u, v) = GlobeView.textureCoordinate(in: view, at: g.location(in: view))
            else { return }
            onTap(u, v)
        }
    }
}

/// `allowsCameraControl` swallows its gestures, so the cheapest way to know the user has taken
/// over is the touch itself.
private final class TouchReportingSCNView: SCNView {
    var onFirstTouch: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onFirstTouch?()
        onFirstTouch = nil
        super.touchesBegan(touches, with: event)
    }
}
