import BikeinsideCore
import SceneKit
import simd

/// Low-poly cyclist on a road bike, built from SceneKit primitives and animated
/// procedurally: wheels spin with speed, cranks with cadence and the legs follow
/// the pedals with two-bone IK. Faces +X; +Y is up; +Z is the rider's right.
final class RiderAvatar {
    let node = SCNNode()
    private let bikeNode = SCNNode()
    private let frontWheel = SCNNode()
    private let rearWheel = SCNNode()
    private let crank = SCNNode()
    private var legs: [(thigh: SCNNode, shin: SCNNode, foot: SCNNode, side: Float)] = []
    private let torso = SCNNode()
    private let headNode = SCNNode()
    private var label: SCNNode?

    private var crankAngle: Double = 0
    private var wheelAngle: Double = 0
    private var bob: Double = 0

    // Geometry (metres) – scaled by rider height.
    private let wheelRadius: Float = 0.34
    private let bb = SIMD2<Float>(0, 0.29)
    private let crankLength: Float = 0.17
    private let hip: SIMD2<Float>
    private let thighLength: Float
    private let shinLength: Float

    var headPosition: SCNVector3 { headNode.worldPosition }

    init(jersey: NSColor, name: String?, heightCm: Double, showName: Bool) {
        let s = Float(heightCm / 180)
        hip = SIMD2<Float>(-0.16, 0.90 * min(max(s, 0.9), 1.1))
        thighLength = 0.45 * s
        shinLength = 0.44 * s

        let frameColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        let frameMat = Materials.solid(frameColor, roughness: 0.35, metalness: 0.6)
        let accentMat = Materials.solid(jersey, roughness: 0.4)
        let tyreMat = Materials.solid(NSColor(calibratedWhite: 0.05, alpha: 1), roughness: 0.9)
        let rimMat = Materials.solid(NSColor(calibratedWhite: 0.7, alpha: 1), roughness: 0.3, metalness: 0.9)
        let jerseyMat = Materials.solid(jersey, roughness: 0.7)
        let shortsMat = Materials.solid(NSColor(calibratedWhite: 0.06, alpha: 1), roughness: 0.8)
        let skinMat = Materials.solid(NSColor(calibratedRed: 0.87, green: 0.68, blue: 0.55, alpha: 1), roughness: 0.75)
        let shoeMat = Materials.solid(NSColor(calibratedWhite: 0.95, alpha: 1), roughness: 0.5)
        let helmetMat = Materials.solid(jersey.blended(withFraction: 0.35, of: .white) ?? jersey, roughness: 0.3)

        node.addChildNode(bikeNode)

        // Wheels: tyre torus + rim + a few spokes (makes rotation visible)
        for (wheel, x) in [(rearWheel, Float(-0.5)), (frontWheel, Float(0.52))] {
            wheel.simdPosition = SIMD3(x, wheelRadius, 0)
            let tyre = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(wheelRadius - 0.012), pipeRadius: 0.014))
            tyre.geometry?.materials = [tyreMat]
            tyre.eulerAngles.x = .pi / 2
            wheel.addChildNode(tyre)
            let rim = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(wheelRadius - 0.035), pipeRadius: 0.008))
            rim.geometry?.materials = [rimMat]
            rim.eulerAngles.x = .pi / 2
            wheel.addChildNode(rim)
            for k in 0..<6 {
                let spoke = SCNNode(geometry: SCNCylinder(radius: 0.003, height: CGFloat(2 * (wheelRadius - 0.04))))
                spoke.geometry?.materials = [rimMat]
                spoke.eulerAngles.z = CGFloat(Double(k) * .pi / 6)
                wheel.addChildNode(spoke)
            }
            let hub = SCNNode(geometry: SCNCylinder(radius: 0.025, height: 0.1))
            hub.geometry?.materials = [frameMat]
            hub.eulerAngles.x = .pi / 2
            wheel.addChildNode(hub)
            bikeNode.addChildNode(wheel)
        }

        // Frame tubes
        let rear = SIMD3<Float>(-0.5, wheelRadius, 0)
        let front = SIMD3<Float>(0.52, wheelRadius, 0)
        let bb3 = SIMD3<Float>(bb.x, bb.y, 0)
        let seatTop = SIMD3<Float>(-0.15, 0.80, 0)
        let headTop = SIMD3<Float>(0.40, 0.78, 0)
        let headBottom = SIMD3<Float>(0.44, 0.62, 0)
        func tube(_ a: SIMD3<Float>, _ b: SIMD3<Float>, r: CGFloat, mat: SCNMaterial) {
            let len = CGFloat(((b - a) * (b - a)).sum().squareRoot())
            let n = SCNNode(geometry: SCNCylinder(radius: r, height: len))
            n.geometry?.materials = [mat]
            align(n, from: a, to: b)
            bikeNode.addChildNode(n)
        }
        tube(bb3, seatTop, r: 0.018, mat: accentMat)
        tube(seatTop, headTop, r: 0.017, mat: accentMat)
        tube(bb3, headBottom, r: 0.022, mat: accentMat)
        tube(headBottom, headTop, r: 0.02, mat: frameMat)
        for z: Float in [-0.05, 0.05] {
            tube(bb3 + SIMD3(0, 0, z), rear + SIMD3(0, 0, z), r: 0.011, mat: frameMat)
            tube(seatTop + SIMD3(0, 0, z * 0.5), rear + SIMD3(0, 0, z), r: 0.01, mat: frameMat)
            tube(headBottom + SIMD3(0, 0, z * 0.4), front + SIMD3(0, 0, z), r: 0.012, mat: frameMat)
        }
        // seatpost + saddle
        let saddleTop = SIMD3<Float>(hip.x - 0.02, hip.y - 0.06, 0)
        tube(seatTop, saddleTop, r: 0.012, mat: frameMat)
        let saddle = SCNNode(geometry: SCNBox(width: 0.26, height: 0.03, length: 0.12, chamferRadius: 0.015))
        saddle.geometry?.materials = [shortsMat]
        saddle.simdPosition = saddleTop + SIMD3(0, 0.015, 0)
        bikeNode.addChildNode(saddle)
        // stem + handlebar
        let barCenter = SIMD3<Float>(0.50, 0.84, 0)
        tube(headTop, barCenter, r: 0.014, mat: frameMat)
        let bar = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.42))
        bar.geometry?.materials = [frameMat]
        bar.eulerAngles.x = .pi / 2
        bar.simdPosition = barCenter
        bikeNode.addChildNode(bar)
        for z: Float in [-0.2, 0.2] { // drops
            tube(barCenter + SIMD3(0, 0, z), barCenter + SIMD3(0.08, -0.12, z), r: 0.012, mat: frameMat)
        }

        // Crankset
        crank.simdPosition = bb3
        let ring = SCNNode(geometry: SCNCylinder(radius: 0.1, height: 0.006))
        ring.geometry?.materials = [rimMat]
        ring.eulerAngles.x = .pi / 2
        ring.simdPosition = SIMD3(0, 0, 0.06)
        crank.addChildNode(ring)
        for (z, phase) in [(Float(0.08), Float(0)), (Float(-0.08), Float.pi)] {
            let arm = SCNNode(geometry: SCNBox(width: CGFloat(crankLength), height: 0.02, length: 0.012, chamferRadius: 0.004))
            arm.geometry?.materials = [frameMat]
            let pivot = SCNNode()
            pivot.simdPosition = SIMD3(0, 0, z)
            pivot.eulerAngles.z = CGFloat(phase)
            arm.simdPosition = SIMD3(crankLength / 2, 0, 0)
            pivot.addChildNode(arm)
            crank.addChildNode(pivot)
        }
        bikeNode.addChildNode(crank)

        // Rider body
        let shoulder = SIMD3<Float>(0.27, 1.30 * min(max(s, 0.9), 1.1), 0)
        let hip3 = SIMD3<Float>(hip.x, hip.y, 0)
        let torsoLen = CGFloat(((shoulder - hip3) * (shoulder - hip3)).sum().squareRoot())
        torso.geometry = SCNCapsule(capRadius: 0.15, height: torsoLen + 0.2)
        torso.geometry?.materials = [jerseyMat]
        align(torso, from: hip3, to: shoulder)
        torso.scale = SCNVector3(1, 1, 1.15)
        node.addChildNode(torso)

        headNode.geometry = SCNSphere(radius: 0.1)
        headNode.geometry?.materials = [skinMat]
        headNode.simdPosition = shoulder + SIMD3(0.12, 0.17, 0)
        let helmet = SCNNode(geometry: SCNSphere(radius: 0.125))
        helmet.geometry?.materials = [helmetMat]
        helmet.scale = SCNVector3(1.25, 0.85, 1)
        helmet.simdPosition = SIMD3(-0.02, 0.04, 0)
        headNode.addChildNode(helmet)
        node.addChildNode(headNode)

        // Arms: shoulder → elbow → hands on the hoods
        for z: Float in [-0.17, 0.17] {
            let sh = shoulder + SIMD3(0, -0.03, z)
            let hand = barCenter + SIMD3(0.03, 0.02, z * 1.15)
            let elbow = (sh + hand) / 2 + SIMD3(-0.05, -0.04, z * 0.15)
            for (a, b, mat, r) in [(sh, elbow, jerseyMat, CGFloat(0.045)), (elbow, hand, skinMat, CGFloat(0.035))] {
                let len = CGFloat(((b - a) * (b - a)).sum().squareRoot())
                let n = SCNNode(geometry: SCNCapsule(capRadius: r, height: len + 2 * r))
                n.geometry?.materials = [mat]
                align(n, from: a, to: b)
                node.addChildNode(n)
            }
        }

        // Legs (animated)
        for side: Float in [-0.1, 0.1] {
            let thigh = SCNNode(geometry: SCNCapsule(capRadius: 0.07, height: CGFloat(thighLength) + 0.12))
            thigh.geometry?.materials = [shortsMat]
            let shin = SCNNode(geometry: SCNCapsule(capRadius: 0.05, height: CGFloat(shinLength) + 0.08))
            shin.geometry?.materials = [skinMat]
            let foot = SCNNode(geometry: SCNBox(width: 0.24, height: 0.07, length: 0.09, chamferRadius: 0.03))
            foot.geometry?.materials = [shoeMat]
            node.addChildNode(thigh)
            node.addChildNode(shin)
            node.addChildNode(foot)
            legs.append((thigh, shin, foot, side))
        }

        if showName, let name {
            let text = SCNText(string: name, extrusionDepth: 0)
            text.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            text.flatness = 0.2
            text.firstMaterial = Materials.solid(.white)
            text.firstMaterial?.lightingModel = .constant
            let tn = SCNNode(geometry: text)
            let (minB, maxB) = tn.boundingBox
            tn.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
            tn.scale = SCNVector3(0.025, 0.025, 0.025)
            let holder = SCNNode()
            holder.position = SCNVector3(0.1, 2.0, 0)
            holder.addChildNode(tn)
            holder.constraints = [SCNBillboardConstraint()]
            node.addChildNode(holder)
            label = holder
        }

        node.enumerateHierarchy { n, _ in n.castsShadow = true }
        pose(crankAngle: 0)
    }

    /// Advance animation.
    func animate(dt: Double, speed: Double, cadence: Double, power: Double) {
        wheelAngle -= speed / Double(wheelRadius) * dt
        frontWheel.eulerAngles.z = CGFloat(wheelAngle)
        rearWheel.eulerAngles.z = CGFloat(wheelAngle)
        // Pedalling forward = crank rotates clockwise seen from the right (+Z) → negative angle about Z.
        let rpm = cadence > 1 ? cadence : (power > 5 ? 80 : 0)
        crankAngle -= rpm / 60 * 2 * .pi * dt
        crank.eulerAngles.z = CGFloat(crankAngle)
        pose(crankAngle: crankAngle)
        // slight lateral sway of the bike under hard efforts (standing feel)
        bob += dt * rpm / 60 * 2 * .pi
        let sway = sin(bob) * min(max(power - 250, 0) / 500, 1) * 0.06
        bikeNode.eulerAngles.x = CGFloat(sway)
    }

    private func pose(crankAngle a: Double) {
        for (k, leg) in legs.enumerated() {
            let angle = a + (k == 0 ? .pi : 0) // left leg opposite
            let pedal = LegIK.pedal(bottomBracket: Vec2(Double(bb.x), Double(bb.y)), crankLength: Double(crankLength), angle: angle)
            let hip2 = Vec2(Double(hip.x), Double(hip.y))
            // foot sits slightly above and behind the pedal axle
            let ankle = pedal + Vec2(-0.03, 0.05)
            let knee = LegIK.knee(hip: hip2, foot: ankle, upper: Double(thighLength), lower: Double(shinLength))
            let z = leg.side
            let hip3 = SIMD3<Float>(hip.x, hip.y, z)
            let knee3 = SIMD3<Float>(Float(knee.x), Float(knee.y), z * 1.05)
            let ankle3 = SIMD3<Float>(Float(ankle.x), Float(ankle.y), z * 1.1)
            align(leg.thigh, from: hip3, to: knee3)
            align(leg.shin, from: knee3, to: ankle3)
            leg.foot.simdPosition = SIMD3(Float(pedal.x) + 0.03, Float(pedal.y) + 0.02, z * 1.1)
        }
    }

    func setLabelVisible(_ visible: Bool) { label?.isHidden = !visible }
}
