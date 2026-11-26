import AppKit
import BikeinsideCore
import RealityKit
import simd

/// RealityKit scene for a ride: landscape, sky, riders, sun and camera.
@MainActor
final class WorldScene {
    let root = Entity()
    let camera = PerspectiveCamera()
    private let sun = DirectionalLight()
    private let sky: ModelEntity
    private let player: RiderEntity
    private var bots: [String: RiderEntity] = [:]
    private let route: Route
    private let terrain: Terrain
    private let atmosphere: Atmosphere

    private var camPos = SIMD3<Float>(0, 5, 10)
    private var camTarget = SIMD3<Float>(0, 1, 0)
    private var hasCamera = false

    init(route: Route, geometry: WorldGeometry, rider: RiderProfile, bots botProfiles: [BotProfile], showNames: Bool) throws {
        self.route = route
        terrain = geometry.terrain
        atmosphere = Atmosphere.forTheme(route.theme)
        let materials = try WorldMaterials(fogColor: atmosphere.fogLinear, fogEnd: atmosphere.fogEnd)

        // Sky dome (unlit, follows the camera) + image-based ambient light from the same sky.
        let skyImage = atmosphere.skyImage(seed: route.seed)
        var skyMaterial = UnlitMaterial(color: atmosphere.sunColor)
        if let skyImage, let tex = try? TextureResource.generate(from: skyImage, options: .init(semantic: .color)) {
            skyMaterial.color = .init(tint: .white, texture: .init(tex))
        }
        skyMaterial.faceCulling = .front
        sky = ModelEntity(mesh: .generateSphere(radius: 1), materials: [skyMaterial])
        sky.scale = SIMD3(repeating: 4000)
        root.addChild(sky)

        var receivers: [Entity] = []
        let ibl = Entity()
        if let skyImage, let env = try? EnvironmentResource.generate(fromEquirectangular: skyImage) {
            ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: atmosphere.ambientExponent))
        }
        root.addChild(ibl)

        func add(_ mesh: Mesh, material: CustomMaterial, shadows: Bool) throws {
            guard !mesh.isEmpty else { return }
            let e = ModelEntity(mesh: try mesh.meshResource(), materials: [material])
            e.components.set(DynamicLightShadowComponent(castsShadow: shadows))
            root.addChild(e)
            receivers.append(e)
        }
        for c in geometry.terrainChunks { try add(c.mesh, material: materials.ground, shadows: false) }
        for c in geometry.sceneryChunks { try add(c.mesh, material: materials.ground, shadows: true) }
        try add(geometry.road, material: materials.ground, shadows: false)
        try add(geometry.arches, material: materials.ground, shadows: true)
        if let w = geometry.water { try add(w, material: materials.water, shadows: false) }

        // Sun with shadows that follow the camera.
        sun.light = DirectionalLightComponent(color: atmosphere.sunColor, intensity: atmosphere.sunIntensity)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 90, depthBias: 2)
        sun.orientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(atmosphere.sunDirection))
        root.addChild(sun)

        camera.camera = PerspectiveCameraComponent(near: 0.1, far: 6000, fieldOfViewInDegrees: 62)
        root.addChild(camera)

        // Riders
        let shared = try RiderEntity.SharedMeshes()
        player = try RiderEntity(jersey: RiderProfile.jerseyPalette[rider.jerseyColorIndex], heightCm: rider.heightCm,
                                 name: nil, shared: shared, material: materials.ground)
        root.addChild(player.root)
        receivers.append(player.root)
        for b in botProfiles {
            let r = try RiderEntity(jersey: RiderProfile.jerseyPalette[b.jerseyColorIndex % RiderProfile.jerseyPalette.count],
                                    heightCm: b.heightCm, name: showNames ? b.name : nil, shared: shared, material: materials.ground)
            bots[b.id] = r
            root.addChild(r.root)
            receivers.append(r.root)
        }

        // Ambient light applies to every model that opts in.
        for e in receivers {
            e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
            for child in e.children { child.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl)) }
            for child in e.children.flatMap(\.children) { child.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl)) }
        }
    }

    private func roadPose(distance: Double, lateral: Double) -> (position: SIMD3<Float>, heading: SIMD2<Float>, grade: Float) {
        let s = route.sample(at: distance)
        let right = Vec3(-s.heading.y, 0, s.heading.x)
        let p = s.position + right * lateral + Vec3(0, 0.06, 0)
        return (SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)), SIMD2<Float>(Float(s.heading.x), Float(s.heading.y)), Float(s.grade))
    }

    func update(engine: RideEngine, dt: Double, cameraMode: CameraMode) {
        let me = roadPose(distance: engine.distance, lateral: engine.riderLateral)
        player.place(at: me.position, heading: me.heading, grade: me.grade)
        player.animate(dt: dt, speed: engine.speed, cadence: engine.cadence ?? 0, power: engine.power)

        for b in engine.bots {
            guard let avatar = bots[b.profile.id] else { continue }
            let near = abs(b.distance - engine.distance) < 1200
            avatar.isHidden = !near
            guard near else { continue }
            let pose = roadPose(distance: b.distance, lateral: b.lateral)
            avatar.place(at: pose.position, heading: pose.heading, grade: pose.grade)
            avatar.animate(dt: dt, speed: b.speed, cadence: 88, power: b.power)
        }

        updateCamera(rider: me.position, heading: me.heading, grade: me.grade, mode: cameraMode, dt: dt)
        player.isHidden = cameraMode == .firstPerson
        sky.position = camPos
    }

    private func updateCamera(rider p: SIMD3<Float>, heading h: SIMD2<Float>, grade: Float, mode: CameraMode, dt: Double) {
        let fwd = simd_normalize(SIMD3<Float>(h.x, 0, h.y))
        let right = SIMD3<Float>(-fwd.z, 0, fwd.x)
        let up = SIMD3<Float>(0, 1, 0)
        var pos: SIMD3<Float>
        var target: SIMD3<Float>
        var rate: Double = 4
        switch mode {
        case .chase:
            // high enough that the rider sits low in frame and the road ahead is visible
            pos = p - fwd * 6.5 + up * 3.0
            target = p + fwd * 14 + up * 0.4
        case .close:
            pos = p - fwd * 3.2 + up * 1.7 + right * 0.9
            target = p + fwd * 6 + up * 0.9
        case .firstPerson:
            pos = p + fwd * 0.45 + up * 1.62
            target = p + fwd * 25 + up * (1.4 + grade * 25)
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
        let ground = Float(terrain.height(x: Double(camPos.x), z: Double(camPos.z)))
        camPos.y = max(camPos.y, ground + 0.6, p.y + 0.4)
        camera.look(at: camTarget, from: camPos, relativeTo: nil)
    }
}
