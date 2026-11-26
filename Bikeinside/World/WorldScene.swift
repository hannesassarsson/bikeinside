import BikeinsideCore
import SceneKit
import simd

/// Look and light for each landscape theme.
struct Atmosphere {
    var zenith: SIMD3<Double>
    var horizon: SIMD3<Double>
    var sunDirection: SIMD3<Float> // direction light travels (from sun to ground)
    var sunColor: NSColor
    var sunIntensity: CGFloat
    var ambientIntensity: CGFloat
    var fogStart: CGFloat
    var fogEnd: CGFloat
    var cloudiness: Double

    static func forTheme(_ theme: SceneryTheme) -> Atmosphere {
        switch theme {
        case .forest:
            return Atmosphere(
                zenith: SIMD3(0.22, 0.45, 0.82), horizon: SIMD3(0.72, 0.82, 0.90),
                sunDirection: SIMD3(-0.45, -0.78, -0.35), sunColor: NSColor(calibratedRed: 1, green: 0.96, blue: 0.88, alpha: 1),
                sunIntensity: 1900, ambientIntensity: 420, fogStart: 250, fogEnd: 1500, cloudiness: 0.45)
        case .lake:
            return Atmosphere(
                zenith: SIMD3(0.28, 0.42, 0.75), horizon: SIMD3(0.96, 0.80, 0.62),
                sunDirection: SIMD3(0.55, -0.42, -0.6), sunColor: NSColor(calibratedRed: 1, green: 0.84, blue: 0.64, alpha: 1),
                sunIntensity: 1700, ambientIntensity: 380, fogStart: 350, fogEnd: 1900, cloudiness: 0.3)
        case .mountain:
            return Atmosphere(
                zenith: SIMD3(0.12, 0.32, 0.72), horizon: SIMD3(0.70, 0.80, 0.92),
                sunDirection: SIMD3(-0.3, -0.7, 0.55), sunColor: NSColor(calibratedRed: 1, green: 0.97, blue: 0.92, alpha: 1),
                sunIntensity: 2100, ambientIntensity: 400, fogStart: 600, fogEnd: 2600, cloudiness: 0.25)
        }
    }

    var horizonColor: NSColor { NSColor(calibratedRed: horizon.x, green: horizon.y, blue: horizon.z, alpha: 1) }

    /// Equirectangular sky (2:1) with a vertical gradient and soft procedural clouds.
    func skyImage(seed: UInt64) -> CGImage? {
        let w = 1024, h = 512
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        let noise = ValueNoise2D(seed: seed)
        for y in 0..<h {
            let elev = (0.5 - (Double(y) + 0.5) / Double(h)) * .pi // +π/2 top … −π/2 bottom
            let up = max(sin(elev), 0)
            var base: SIMD3<Double>
            if elev >= 0 {
                let t = pow(up, 0.45)
                base = horizon + (zenith - horizon) * t
            } else {
                base = horizon * 0.98 // below horizon = fog colour so terrain edges vanish
            }
            for x in 0..<w {
                var c = base
                if elev > 0.02 && cloudiness > 0 {
                    let u = Double(x) / Double(w) * 2 * .pi
                    // project onto a cloud plane so clouds flatten towards the horizon
                    let r = 1 / max(sin(elev), 0.08)
                    let px = cos(u) * r * 1.2, pz = sin(u) * r * 1.2
                    let n = noise.fbm(px + 10, pz - 4, octaves: 5) * 0.5 + 0.5
                    let cover = Interp.smoothstep(1 - cloudiness * 0.9, 1.05 - cloudiness * 0.5, n)
                    let fade = Interp.smoothstep(0.02, 0.25, elev)
                    let cloud = SIMD3<Double>(0.97, 0.97, 0.98) * (0.86 + 0.14 * up)
                    c = c + (cloud - c) * (cover * fade * 0.85)
                }
                let i = (y * w + x) * 4
                pixels[i] = UInt8(Interp.clamp(c.x, 0, 1) * 255)
                pixels[i + 1] = UInt8(Interp.clamp(c.y, 0, 1) * 255)
                pixels[i + 2] = UInt8(Interp.clamp(c.z, 0, 1) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Owns the SceneKit scene for a ride: landscape, riders, lights and camera.
@MainActor
final class WorldScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let sunNode = SCNNode()
    private let player: RiderAvatar
    private var bots: [String: RiderAvatar] = [:]
    private let route: Route
    private let terrain: Terrain
    private let atmosphere: Atmosphere

    private var camPos = SIMD3<Float>(0, 5, 10)
    private var camTarget = SIMD3<Float>(0, 1, 0)
    private var hasCamera = false

    init(route: Route, geometry: WorldGeometry, rider: RiderProfile, bots botProfiles: [BotProfile], showNames: Bool) {
        self.route = route
        terrain = geometry.terrain
        atmosphere = Atmosphere.forTheme(route.theme)

        // Sky, image-based lighting and fog
        if let sky = atmosphere.skyImage(seed: route.seed) {
            scene.background.contents = sky
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 1.1
        }
        scene.fogColor = atmosphere.horizonColor
        scene.fogStartDistance = atmosphere.fogStart
        scene.fogEndDistance = atmosphere.fogEnd
        scene.fogDensityExponent = 1.3

        // Landscape
        let ground = Materials.vertexColored(roughness: 0.95)
        for chunk in geometry.terrainChunks {
            let n = SCNNode(geometry: chunk.mesh.scnGeometry(material: ground))
            n.castsShadow = false
            scene.rootNode.addChildNode(n)
        }
        let foliage = Materials.vertexColored(roughness: 0.85)
        for chunk in geometry.sceneryChunks {
            let n = SCNNode(geometry: chunk.mesh.scnGeometry(material: foliage))
            n.castsShadow = true
            scene.rootNode.addChildNode(n)
        }
        let roadMat = Materials.vertexColored(roughness: 0.75)
        let road = SCNNode(geometry: geometry.road.scnGeometry(material: roadMat))
        road.castsShadow = false
        scene.rootNode.addChildNode(road)
        let arches = SCNNode(geometry: geometry.arches.scnGeometry(material: Materials.vertexColored(roughness: 0.5)))
        scene.rootNode.addChildNode(arches)

        if let w = route.waterLevel {
            let t = geometry.terrain
            let plane = SCNPlane(width: CGFloat(t.width + 4000), height: CGFloat(t.depth + 4000))
            let water = SCNMaterial()
            water.lightingModel = .physicallyBased
            water.diffuse.contents = NSColor(calibratedRed: 0.10, green: 0.26, blue: 0.36, alpha: 1)
            water.roughness.contents = 0.08
            water.metalness.contents = 0.0
            water.transparency = 0.92
            water.writesToDepthBuffer = true
            plane.materials = [water]
            let wn = SCNNode(geometry: plane)
            wn.eulerAngles.x = -.pi / 2
            wn.simdPosition = SIMD3<Float>(Float(t.originX + t.width / 2), Float(w), Float(t.originZ + t.depth / 2))
            wn.castsShadow = false
            scene.rootNode.addChildNode(wn)
        }

        // Lights
        let sun = SCNLight()
        sun.type = .directional
        sun.color = atmosphere.sunColor
        sun.intensity = atmosphere.sunIntensity
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
        sun.automaticallyAdjustsShadowProjection = false
        sun.orthographicScale = 45
        sun.zNear = 1
        sun.zFar = 600
        sunNode.light = sun
        sunNode.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: simd_normalize(atmosphere.sunDirection))
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = atmosphere.ambientIntensity
        ambient.color = NSColor(calibratedRed: 0.75, green: 0.82, blue: 1.0, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Camera
        let cam = SCNCamera()
        cam.fieldOfView = 62
        cam.zNear = 0.1
        cam.zFar = 3500
        cam.wantsHDR = true
        cam.bloomIntensity = 0.25
        cam.bloomThreshold = 0.9
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0
        cam.vignettingIntensity = 0.25
        cam.vignettingPower = 0.6
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)

        // Riders
        player = RiderAvatar(jersey: Self.color(RiderProfile.jerseyPalette[rider.jerseyColorIndex]), name: nil, heightCm: rider.heightCm, showName: false)
        scene.rootNode.addChildNode(player.node)
        for b in botProfiles {
            let a = RiderAvatar(jersey: Self.color(RiderProfile.jerseyPalette[b.jerseyColorIndex % RiderProfile.jerseyPalette.count]),
                                name: b.name, heightCm: b.heightCm, showName: showNames)
            bots[b.id] = a
            scene.rootNode.addChildNode(a.node)
        }
    }

    static func color(_ c: SIMD3<Double>) -> NSColor {
        NSColor(calibratedRed: c.x, green: c.y, blue: c.z, alpha: 1)
    }

    /// World transform for a rider at a route distance and lateral offset (m right of centre).
    private func place(_ avatar: RiderAvatar, distance: Double, lateral: Double) -> (position: SIMD3<Float>, heading: SIMD3<Float>) {
        let s = route.sample(at: distance)
        let right = Vec3(-s.heading.y, 0, s.heading.x)
        let p = s.position + right * lateral + Vec3(0, 0.06, 0)
        let yaw = atan2(-s.heading.y, s.heading.x)
        avatar.node.eulerAngles = SCNVector3(0, CGFloat(yaw), CGFloat(atan(s.grade)))
        let pf = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
        avatar.node.simdPosition = pf
        return (pf, SIMD3<Float>(Float(s.heading.x), Float(s.grade), Float(s.heading.y)))
    }

    func update(engine: RideEngine, dt: Double, cameraMode: CameraMode) {
        let me = place(player, distance: engine.distance, lateral: engine.riderLateral)
        player.animate(dt: dt, speed: engine.speed, cadence: engine.cadence ?? 0, power: engine.power)

        for b in engine.bots {
            guard let avatar = bots[b.profile.id] else { continue }
            // Only animate riders that are reasonably close.
            let near = abs(b.distance - engine.distance) < 1200
            avatar.node.isHidden = !near
            guard near else { continue }
            _ = place(avatar, distance: b.distance, lateral: b.lateral)
            avatar.animate(dt: dt, speed: b.speed, cadence: 88, power: b.power)
        }

        // Keep the shadow frustum centred on the rider.
        let sunDir = simd_normalize(atmosphere.sunDirection)
        sunNode.simdPosition = me.position - sunDir * 250

        updateCamera(rider: me.position, heading: me.heading, mode: cameraMode, dt: dt)
        player.node.isHidden = (cameraMode == .firstPerson)
    }

    private func updateCamera(rider p: SIMD3<Float>, heading h: SIMD3<Float>, mode: CameraMode, dt: Double) {
        let fwd = simd_normalize(SIMD3<Float>(h.x, 0, h.z))
        let right = SIMD3<Float>(-fwd.z, 0, fwd.x)
        let up = SIMD3<Float>(0, 1, 0)
        var pos: SIMD3<Float>
        var target: SIMD3<Float>
        var rate: Double = 4
        switch mode {
        case .chase:
            pos = p - fwd * 5.8 + up * 2.3
            target = p + fwd * 6 + up * 1.0
        case .close:
            pos = p - fwd * 3.0 + up * 1.5 + right * 0.6
            target = p + fwd * 3 + up * 1.0
        case .firstPerson:
            pos = p + fwd * 0.45 + up * 1.62
            target = p + fwd * 25 + up * (1.4 + h.y * 25)
            rate = 12
        case .side:
            pos = p + right * 6 + up * 1.6 - fwd * 1
            target = p + up * 0.9 + fwd * 0.5
        case .drone:
            pos = p - fwd * 22 + up * 14 + right * 6
            target = p + fwd * 10
            rate = 2
        }
        if !hasCamera {
            camPos = pos
            camTarget = target
            hasCamera = true
        } else {
            let k = Float(Interp.damp(rate: rate, dt: dt))
            camPos += (pos - camPos) * k
            camTarget += (target - camTarget) * min(k * 1.5, 1)
        }
        // Never put the camera under the terrain or the road.
        let ground = Float(terrain.height(x: Double(camPos.x), z: Double(camPos.z)))
        camPos.y = max(camPos.y, ground + 0.6, p.y + 0.4)
        cameraNode.simdPosition = camPos
        cameraNode.simdLook(at: camTarget, up: up, localFront: SIMD3<Float>(0, 0, -1))
    }
}
