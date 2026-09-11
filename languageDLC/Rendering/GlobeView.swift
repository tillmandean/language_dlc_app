import SwiftUI
import SceneKit
import QuartzCore

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
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        context.coordinator.view = view
        context.coordinator.globe = globe
        context.coordinator.camera = built.camera
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
        weak var globe: SCNNode?
        weak var camera: SCNNode?
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

        // MARK: - Rotation (drag) and momentum

        /// Radians per point of drag translation or per point/second of release velocity — the
        /// same factor for both keeps a flick feel like a continuation of the drag that caused it.
        private static let rotationScale: Double = 0.005
        private static let maxPitch: Float = 80 * .pi / 180   // never flip over a pole

        private(set) var pitch: Float = 0    // rotation around X, exposed for the pitch-clamp test
        private(set) var yaw: Float = 0      // rotation around Y

        private var angularVelocityX: Double = 0   // rad/s, decaying after a flick
        private var angularVelocityY: Double = 0
        private var displayLink: CADisplayLink?
        private var lastMomentumTimestamp: CFTimeInterval?

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view else { return }
            switch g.state {
            case .began:
                stopMomentum()
            case .changed:
                let t = g.translation(in: view)
                g.setTranslation(.zero, in: view)
                applyRotation(dx: Double(t.x), dy: Double(t.y))
            case .ended:
                let v = g.velocity(in: view)
                angularVelocityY = Double(v.x) * Self.rotationScale
                angularVelocityX = Double(v.y) * Self.rotationScale
                startMomentum()
            default:
                break
            }
        }

        /// `dx`, `dy` are points of drag translation. Not private so tests can drive it directly
        /// without a real `UIPanGestureRecognizer`.
        func applyRotation(dx: Double, dy: Double) {
            rotate(byYaw: Float(dx * Self.rotationScale), pitch: Float(dy * Self.rotationScale))
        }

        private func rotate(byYaw dYaw: Float, pitch dPitch: Float) {
            yaw += dYaw
            pitch = min(max(pitch + dPitch, -Self.maxPitch), Self.maxPitch)
            globe?.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        private func startMomentum() {
            guard angularVelocityX != 0 || angularVelocityY != 0 else { return }
            lastMomentumTimestamp = nil
            let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopMomentum() {
            displayLink?.invalidate()
            displayLink = nil
            angularVelocityX = 0
            angularVelocityY = 0
        }

        /// Exponential decay tuned so a flick's rotation has mostly died out by `momentumDuration`.
        private static let momentumDuration: CFTimeInterval = 0.8
        private static let momentumTimeConstant = momentumDuration / 3
        private static let stopThreshold = 0.01   // rad/s

        @objc private func stepMomentum(_ link: CADisplayLink) {
            defer { lastMomentumTimestamp = link.timestamp }
            guard let last = lastMomentumTimestamp else { return }
            let dt = link.timestamp - last
            guard dt > 0, dt < 1 else { return }

            rotate(byYaw: Float(angularVelocityY * dt), pitch: Float(angularVelocityX * dt))

            let decay = exp(-dt / Self.momentumTimeConstant)
            angularVelocityX *= decay
            angularVelocityY *= decay
            if abs(angularVelocityX) < Self.stopThreshold, abs(angularVelocityY) < Self.stopThreshold {
                stopMomentum()
            }
        }

        // MARK: - Zoom (pinch)

        private static let minCameraZ: Double = 1.6
        private static let maxCameraZ: Double = 6
        private var pinchStartZ: Double = 3

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let camera else { return }
            switch g.state {
            case .began:
                pinchStartZ = Double(camera.position.z)
            case .changed:
                let z = min(max(pinchStartZ / Double(g.scale), Self.minCameraZ), Self.maxCameraZ)
                camera.position.z = Float(z)
            default:
                break
            }
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
