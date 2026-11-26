import AppKit
import BikeinsideCore
import RealityKit
import simd

/// Animated cyclist in RealityKit: wheels spin with speed, the crank with
/// cadence, and the legs follow the pedals via two-bone IK (from BikeinsideCore).
@MainActor
final class RiderEntity {
    let root = Entity()
    private let frontWheel: ModelEntity
    private let rearWheel: ModelEntity
    private let crank: ModelEntity
    private let bikeBody = Entity()
    private var legs: [(side: Float, thigh: ModelEntity, shin: ModelEntity, knee: ModelEntity, foot: ModelEntity)] = []
    private let geometry: AvatarGeometry

    private var crankAngle: Double = 0
    private var wheelAngle: Double = 0
    private var phase: Double = 0

    /// Shared meshes (identical for every rider).
    struct SharedMeshes {
        let wheel: MeshResource
        let crank: MeshResource
        let thigh: MeshResource
        let shin: MeshResource
        let joint: MeshResource
        let shoe: MeshResource

        @MainActor
        init() throws {
            wheel = try AvatarMeshes.wheel().meshResource()
            crank = try AvatarMeshes.crank().meshResource()
            thigh = try AvatarMeshes.limb(radius: 0.072, color: AvatarMeshes.shorts, endRadius: 0.055, bandColor: AvatarMeshes.skin, bandFrom: 0.72).meshResource()
            shin = try AvatarMeshes.limb(radius: 0.052, color: AvatarMeshes.skin, endRadius: 0.036, bandColor: AvatarMeshes.white, bandFrom: 0.68).meshResource()
            joint = try AvatarMeshes.joint(radius: 0.056, color: AvatarMeshes.skin).meshResource()
            shoe = try AvatarMeshes.shoe().meshResource()
        }
    }

    init(jersey: SIMD3<Double>, heightCm: Double, name: String?, shared: SharedMeshes, material: CustomMaterial) throws {
        geometry = AvatarGeometry(heightCm: heightCm)
        let j = SIMD3<Float>(Float(jersey.x), Float(jersey.y), Float(jersey.z))
        let mats: [RealityKit.Material] = [material]

        root.addChild(bikeBody)
        let bike = ModelEntity(mesh: try AvatarMeshes.bike(accent: j).meshResource(), materials: mats)
        bikeBody.addChild(bike)
        let body = ModelEntity(mesh: try AvatarMeshes.body(jersey: j, geometry: geometry).meshResource(), materials: mats)
        bikeBody.addChild(body)

        rearWheel = ModelEntity(mesh: shared.wheel, materials: mats)
        rearWheel.position = AvatarGeometry.rearAxle
        frontWheel = ModelEntity(mesh: shared.wheel, materials: mats)
        frontWheel.position = AvatarGeometry.frontAxle
        crank = ModelEntity(mesh: shared.crank, materials: mats)
        crank.position = AvatarGeometry.bottomBracket
        bikeBody.addChild(rearWheel)
        bikeBody.addChild(frontWheel)
        bikeBody.addChild(crank)

        for side: Float in [-1, 1] {
            let thigh = ModelEntity(mesh: shared.thigh, materials: mats)
            let shin = ModelEntity(mesh: shared.shin, materials: mats)
            let knee = ModelEntity(mesh: shared.joint, materials: mats)
            let foot = ModelEntity(mesh: shared.shoe, materials: mats)
            for e in [thigh, shin, knee, foot] { bikeBody.addChild(e) }
            legs.append((side, thigh, shin, knee, foot))
        }

        if let name {
            let text = MeshResource.generateText(
                name, extrusionDepth: 0.002, font: .systemFont(ofSize: 0.16, weight: .bold),
                containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
            let label = ModelEntity(mesh: text, materials: [UnlitMaterial(color: .white)])
            let b = text.bounds
            label.position = SIMD3(-b.center.x, 0, 0)
            let holder = Entity()
            holder.position = SIMD3(0.1, 2.0, 0)
            holder.components.set(BillboardComponent())
            holder.addChild(label)
            root.addChild(holder)
        }
        pose()
    }

    /// Places the rider on the road: position, heading (x/z) and grade.
    func place(at p: SIMD3<Float>, heading: SIMD2<Float>, grade: Float) {
        let yaw = atan2(-heading.y, heading.x)
        root.transform = Transform(
            scale: .one,
            rotation: simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: atan(grade), axis: SIMD3(0, 0, 1)),
            translation: p)
    }

    func animate(dt: Double, speed: Double, cadence: Double, power: Double) {
        wheelAngle -= speed / Double(AvatarGeometry.wheelRadius) * dt
        let wq = simd_quatf(angle: Float(wheelAngle), axis: SIMD3(0, 0, 1))
        frontWheel.orientation = wq
        rearWheel.orientation = wq
        let rpm = cadence > 1 ? cadence : (power > 5 ? 80 : 0)
        crankAngle -= rpm / 60 * 2 * .pi * dt
        crank.orientation = simd_quatf(angle: Float(crankAngle), axis: SIMD3(0, 0, 1))
        pose()
        // the bike sways a little under hard efforts
        phase += dt * rpm / 60 * 2 * .pi
        let sway = Float(sin(phase) * min(max(power - 250, 0) / 500, 1) * 0.06)
        bikeBody.orientation = simd_quatf(angle: sway, axis: SIMD3(1, 0, 0))
    }

    private func pose() {
        for leg in legs {
            let l = geometry.leg(crankAngle: crankAngle, side: leg.side)
            orientLimb(leg.thigh, from: l.hip, to: l.knee)
            orientLimb(leg.shin, from: l.knee, to: l.ankle)
            leg.knee.position = l.knee
            leg.foot.position = l.ankle + SIMD3(0.0, -0.04, 0)
        }
    }

    private func orientLimb(_ e: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let d = b - a
        let len = simd_length(d)
        guard len > 1e-5 else { return }
        e.transform = Transform(
            scale: SIMD3(1, len, 1),
            rotation: simd_quatf(from: SIMD3(0, 1, 0), to: d / len),
            translation: a)
    }

    var isHidden: Bool {
        get { !root.isEnabled }
        set { root.isEnabled = !newValue }
    }
}
