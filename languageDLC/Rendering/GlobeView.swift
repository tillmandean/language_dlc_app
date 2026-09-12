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
    /// Set once, in `makeUIView`, to a closure the caller can invoke to snapshot the globe as
    /// currently rendered — used by the share card (Phase 10.3).
    var captureHandler: Binding<(() -> UIImage?)?> = .constant(nil)

    /// Seconds for one idle revolution; cancelled the moment the user touches the globe.
    private static let spinDuration: TimeInterval = 90

    func makeUIView(context: Context) -> SCNView {
        let view = TouchReportingSCNView()
        let built = Self.makeScene()
        view.scene = built.scene
        view.pointOfView = built.camera
        // Transparent so the navy gradient behind the SwiftUI ZStack shows through instead of a
        // flat rectangle — the globe reads as sitting in the background, not on top of it.
        view.backgroundColor = .clear
        view.isOpaque = false
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
        // Pan and pinch share the delegate so they can run together. Without it UIKit lets only
        // the first recognizer to fire claim the gesture: put two fingers down and spread, and
        // whichever won — usually the pan, since the centroid always drifts a little — locked
        // the other out until every finger lifted. Zoom would simply refuse to start.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        context.coordinator.view = view
        context.coordinator.globe = globe
        context.coordinator.camera = built.camera
        // Writing to the binding synchronously here mutates the parent's @State while SwiftUI
        // is still in the middle of this same view update, which is undefined behavior and
        // silently drops the write — the closure never lands, so `captureHandler` stays nil and
        // the share button folds. Deferring to the next run loop turn keeps the write outside
        // the update pass.
        DispatchQueue.main.async {
            captureHandler.wrappedValue = { [weak view] in view?.snapshot() }
        }
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
        // SceneKit's default zNear (1 world unit) is farther than the closest allowed zoom
        // (minCameraZ 1.6, against a radius-1 sphere — as near as 0.6 units away), so pinching
        // all the way in clipped the near cap of the globe away, leaving the screen black. A
        // near plane closer than the sphere itself fixes that at any zoom level.
        camera.camera?.zNear = 0.05
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

        /// Radians of surface arc per point of drag, at the centre of the view — the factor that
        /// makes the globe track the finger instead of sliding out from under it.
        ///
        /// It has to follow the camera, because the arc a point of screen covers shrinks as you
        /// zoom in: at z = 3 a point spans 0.0042 rad, at the closest zoom only 0.0007. A fixed
        /// factor (this was 0.005) is right at exactly one distance and wrong everywhere else —
        /// nearly 7x too fast at full zoom, where the globe bolted away from the finger, and
        /// half as fast as it should be zoomed out.
        ///
        /// Derivation: a point at screen offset x subtends `dθ = 2·tan(halfFOV)/width` at the
        /// camera, and a ray at angle θ from the axis meets the sphere at arc `α = asin(d·sinθ) − θ`
        /// from the centre of the view, whose slope at θ = 0 is `d − 1`. The two compose to the
        /// expression below. Because `fieldOfView` is measured horizontally here, the vertical
        /// factor works out identical — `tan(vHalf) = tan(hHalf)·height/width` cancels the height —
        /// so one scale serves both axes and a diagonal drag stays straight.
        private var rotationScale: Double {
            guard let view, let camera, let cam = camera.camera else { return Self.fallbackRotationScale }
            let width = Double(view.bounds.width)
            guard width > 0 else { return Self.fallbackRotationScale }
            let halfFOV = Double(cam.fieldOfView) * .pi / 360      // degrees -> half-angle radians
            return max(0, Double(camera.position.z) - 1) * 2 * tan(halfFOV) / width
        }

        /// Used only when there's no view to measure — the unit tests drive `applyRotation`
        /// directly. Matches what the old constant gave at the default camera distance.
        private static let fallbackRotationScale: Double = 0.005

        private static let maxPitch: Float = 80 * .pi / 180   // never flip over a pole
        /// Within this many radians of the pole, dragging eases off instead of tracking the
        /// finger 1:1 — the same "rubber band" a scroll view uses at its bounds. Below the
        /// threshold (`maxPitch - softZone`) nothing changes from a plain clamp.
        private static let softZone: Float = 20 * .pi / 180
        private static let pitchThreshold: Float = maxPitch - softZone

        private(set) var pitch: Float = 0    // rotation around X, eased near the pole; exposed for tests
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
                angularVelocityY = Double(v.x) * rotationScale
                angularVelocityX = Double(v.y) * rotationScale
                startMomentum()
            default:
                break
            }
        }

        /// `dx`, `dy` are points of drag translation. Not private so tests can drive it directly
        /// without a real `UIPanGestureRecognizer`.
        func applyRotation(dx: Double, dy: Double) {
            let scale = rotationScale
            rotate(byYaw: Float(dx * scale * yawConvergence), pitch: Float(dy * scale))
        }

        /// Meridians converge toward the poles, so a radian of yaw slides the ground under the
        /// finger by only `cos(latitude)` of arc — and the latitude at the centre of the view is
        /// the pitch. Without this, horizontal drags crawl as you tilt toward a pole: at the 80°
        /// limit they cover a sixth of the ground they cover at the equator, which reads as the
        /// globe seizing up just as you get somewhere interesting.
        ///
        /// Capped because the true factor runs away at the pole, where longitude stops meaning
        /// anything — a singularity no amount of scaling fixes, only keeps bounded.
        private var yawConvergence: Double {
            min(1 / max(Double(cos(pitch)), 0.0001), 4)
        }

        private func rotate(byYaw dYaw: Float, pitch dPitch: Float) {
            yaw += dYaw
            pitch = min(max(pitch + dPitch * Self.resistance(at: pitch, moving: dPitch),
                            -Self.maxPitch), Self.maxPitch)
            globe?.simdOrientation = Self.orientation(pitch: pitch, yaw: yaw)
        }

        /// The globe's orientation: spin about its own polar axis first, then tilt the whole
        /// assembly about the screen's horizontal axis. Pitch therefore always turns the globe
        /// about a screen-fixed axis, so a vertical drag moves the map the same way wherever the
        /// globe happens to be facing.
        ///
        /// This has to be composed by hand rather than handed to `eulerAngles`, which multiplies
        /// the other way round: SceneKit reads the triple (pitch, yaw, 0) as `Ry(yaw)·Rx(pitch)`,
        /// making the pitch axis the globe's *own* X, which spins with the yaw. Measured on the
        /// simulator, a downward drag tilted the globe by -0.050 at yaw 0, by 0.000 at yaw 90 —
        /// side-on to the axis, so it rolled instead of tilting — and by +0.050 at yaw 180. Spin
        /// round to Asia and dragging down pulled the map up.
        static func orientation(pitch: Float, yaw: Float) -> simd_quatf {
            simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
                * simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        }

        /// How much of a vertical drag reaches the globe: 1 everywhere except the last
        /// `softZone` before a pole, where it falls linearly to 0 so the globe eases to a stop
        /// instead of hitting a wall.
        ///
        /// The resistance applies only while pushing *further* toward the pole. That asymmetry
        /// is the point: the previous version eased a running total of raw drag, so a hard flick
        /// into a pole banked several radians of overshoot that a reverse drag had to pay back
        /// before anything moved — the globe simply stopped responding, sometimes for a whole
        /// screen of dragging. Easing the increment instead leaves nothing to unwind, so the
        /// globe turns on the first pixel of the drag back.
        private static func resistance(at pitch: Float, moving delta: Float) -> Float {
            let magnitude = abs(pitch)
            guard magnitude > pitchThreshold else { return 1 }
            guard delta.sign == pitch.sign else { return 1 }   // heading home: always 1:1
            return max(0, 1 - (magnitude - pitchThreshold) / softZone)
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

        /// Closest the camera may get to the sphere's centre (radius 1), so the nearest approach
        /// to the surface is 0.35 — still well clear of `zNear` (0.05), which is the hard wall at
        /// z = 1.05. The real limit is the texture, not the geometry: the 4096-wide map gives
        /// 11.4 texels per degree, and at this distance the ~17° of arc across a phone screen is
        /// magnified about 6x. Closer than this and the coastlines visibly turn to mush.
        /// Not private: `GlobeRenderingTests` renders at exactly this distance to prove the
        /// near plane still clears the sphere.
        static let closestCameraZ: Double = 1.35
        private static let maxCameraZ: Double = 6
        private var pinchStartZ: Double = 3

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let camera else { return }
            switch g.state {
            case .began:
                pinchStartZ = Double(camera.position.z)
            case .changed:
                let z = min(max(pinchStartZ / Double(g.scale), Self.closestCameraZ), Self.maxCameraZ)
                camera.position.z = Float(z)
            default:
                break
            }
        }
    }
}

extension GlobeView.Coordinator: UIGestureRecognizerDelegate {
    /// Rotating and zooming at once is one continuous two-finger gesture, so pan and pinch have
    /// to recognize simultaneously. Tap stays exclusive — it should only fire on a clean touch.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        !(g is UITapGestureRecognizer) && !(other is UITapGestureRecognizer)
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
