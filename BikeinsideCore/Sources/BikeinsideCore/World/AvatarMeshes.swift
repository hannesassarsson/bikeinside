import Foundation

/// Dimensions of the cyclist + road bike (metres). The bike faces +X, +Y is
/// up and +Z is the rider's right; the ground contact is at y = 0.
public struct AvatarGeometry: Sendable {
    public static let wheelRadius: Float = 0.34
    public static let rearAxle = Float3(-0.5, wheelRadius, 0)
    public static let frontAxle = Float3(0.52, wheelRadius, 0)
    public static let bottomBracket = Float3(0, 0.29, 0)
    public static let crankLength: Float = 0.17
    /// Lateral offset of each foot/leg from the centre plane.
    public static let legOffset: Float = 0.1

    public let hip: Float3
    public let shoulder: Float3
    public let thighLength: Float
    public let shinLength: Float

    public init(heightCm: Double) {
        let s = Float(heightCm / 180)
        let sc = min(max(s, 0.9), 1.1)
        hip = Float3(-0.16, 0.90 * sc, 0)
        shoulder = Float3(0.27, 1.30 * sc, 0)
        thighLength = 0.45 * s
        shinLength = 0.44 * s
    }

    /// Ankle position for a crank angle (radians; forward pedalling decreases it).
    /// `side` is -1 (left) or +1 (right); the left crank is opposite the right.
    public func ankle(crankAngle: Double, side: Float) -> Float3 {
        let a = crankAngle + (side < 0 ? .pi : 0)
        let bb = AvatarGeometry.bottomBracket
        let p = LegIK.pedal(bottomBracket: Vec2(Double(bb.x), Double(bb.y)), crankLength: Double(AvatarGeometry.crankLength), angle: a)
        return Float3(Float(p.x) - 0.03, Float(p.y) + 0.05, side * AvatarGeometry.legOffset * 1.1)
    }

    /// Hip, knee and ankle for one leg.
    public func leg(crankAngle: Double, side: Float) -> (hip: Float3, knee: Float3, ankle: Float3) {
        let ankle = ankle(crankAngle: crankAngle, side: side)
        let k = LegIK.knee(hip: Vec2(Double(hip.x), Double(hip.y)), foot: Vec2(Double(ankle.x), Double(ankle.y)),
                           upper: Double(thighLength), lower: Double(shinLength))
        let z = side * AvatarGeometry.legOffset
        return (Float3(hip.x, hip.y, z), Float3(Float(k.x), Float(k.y), z * 1.05), ankle)
    }
}

/// Low-poly meshes for the animated cyclist. Moving parts (wheels, crank,
/// limbs) are separate meshes so the renderer can transform them each frame.
public enum AvatarMeshes {
    public static let frameDark = Float3(0.12, 0.12, 0.13)
    public static let tyre = Float3(0.05, 0.05, 0.05)
    public static let metal = Float3(0.70, 0.70, 0.72)
    public static let skin = Float3(0.87, 0.68, 0.55)
    public static let shorts = Float3(0.07, 0.07, 0.08)
    public static let shoeWhite = Float3(0.93, 0.93, 0.93)

    public static let white = Float3(0.95, 0.95, 0.95)
    public static let glove = Float3(0.10, 0.10, 0.11)

    /// Frame, fork, saddle, bars, drivetrain and bottle – everything rigid on the bike.
    public static func bike(accent: Float3) -> Mesh {
        var m = Mesh()
        let rear = AvatarGeometry.rearAxle, front = AvatarGeometry.frontAxle
        let bb = AvatarGeometry.bottomBracket
        let seatTop = Float3(-0.15, 0.80, 0)
        let headTop = Float3(0.40, 0.78, 0)
        let headBottom = Float3(0.44, 0.60, 0)
        // main triangle: aero down tube, slim top tube, accent paint with a white decal band
        Primitives.smoothTube(into: &m, from: bb, to: headBottom, radius: 0.026, endRadius: 0.022, sides: 14, color: accent)
        let mid = bb + (headBottom - bb) * 0.55
        Primitives.smoothTube(into: &m, from: mid, to: bb + (headBottom - bb) * 0.75, radius: 0.0265, endRadius: 0.0245, sides: 14, color: white)
        Primitives.smoothTube(into: &m, from: bb, to: seatTop, radius: 0.021, endRadius: 0.018, sides: 12, color: accent)
        Primitives.smoothTube(into: &m, from: seatTop, to: headTop, radius: 0.017, sides: 12, color: accent)
        Primitives.smoothTube(into: &m, from: headBottom + Float3(0.01, -0.03, 0), to: headTop + Float3(-0.005, 0.03, 0), radius: 0.024, sides: 12, color: frameDark)
        Primitives.smoothSphere(into: &m, center: bb, radius: 0.035, color: frameDark)
        for z: Float in [-0.05, 0.05] {
            let o = Float3(0, 0, z)
            Primitives.smoothTube(into: &m, from: bb + o * 0.6, to: rear + o, radius: 0.012, endRadius: 0.009, sides: 8, color: accent)
            Primitives.smoothTube(into: &m, from: seatTop + o * 0.3, to: rear + o, radius: 0.011, endRadius: 0.008, sides: 8, color: accent)
            Primitives.smoothTube(into: &m, from: headBottom + o * 0.4, to: front + o, radius: 0.016, endRadius: 0.010, sides: 8, color: frameDark)
        }
        // seatpost + shaped saddle
        let saddle = Float3(-0.18, 0.865, 0)
        Primitives.smoothTube(into: &m, from: seatTop, to: saddle, radius: 0.013, sides: 8, color: frameDark)
        Primitives.smoothSphere(into: &m, center: saddle + Float3(-0.02, 0.015, 0), radius: 1, scale: Float3(0.13, 0.022, 0.065), color: shorts)
        Primitives.smoothSphere(into: &m, center: saddle + Float3(0.09, 0.012, 0), radius: 1, scale: Float3(0.07, 0.016, 0.025), color: shorts)
        // stem, bars, drops and brake hoods
        let bar = Float3(0.50, 0.84, 0)
        Primitives.smoothTube(into: &m, from: headTop + Float3(0, 0.02, 0), to: bar, radius: 0.015, sides: 8, color: frameDark)
        Primitives.smoothTube(into: &m, from: bar + Float3(0, 0, -0.21), to: bar + Float3(0, 0, 0.21), radius: 0.013, sides: 8, color: frameDark)
        for z: Float in [-0.21, 0.21] {
            let p = bar + Float3(0, 0, z)
            Primitives.smoothTube(into: &m, from: p, to: p + Float3(0.07, -0.02, 0), radius: 0.013, sides: 8, color: frameDark)
            Primitives.smoothTube(into: &m, from: p + Float3(0.07, -0.02, 0), to: p + Float3(0.05, -0.13, 0), radius: 0.013, sides: 8, color: frameDark, roundEnds: true)
            Primitives.smoothSphere(into: &m, center: p + Float3(0.07, 0.01, 0), radius: 1, scale: Float3(0.035, 0.03, 0.018), color: frameDark)
        }
        // drivetrain (right side): chainring, cassette, chain, derailleur
        let z: Float = 0.065
        for k in 0..<24 {
            let a0 = Float(k) / 24 * 2 * .pi, a1 = Float(k + 1) / 24 * 2 * .pi
            let c = bb + Float3(0, 0, z), r = Float(0.105)
            let p0 = c + Float3(cos(a0), sin(a0), 0) * r, p1 = c + Float3(cos(a1), sin(a1), 0) * r
            m.addTriangle(c, p0, p1, color: metal)
            m.addTriangle(c, p1, p0, color: metal * 0.8)
        }
        let cassette = rear + Float3(0, 0, z)
        Primitives.smoothTube(into: &m, from: cassette + Float3(0, 0, -0.02), to: cassette + Float3(0, 0, 0.012), radius: 0.055, endRadius: 0.03, sides: 14, color: metal)
        let chain = Float3(0.20, 0.20, 0.22)
        Primitives.smoothTube(into: &m, from: bb + Float3(0, 0.105, z), to: cassette + Float3(0, 0.05, 0), radius: 0.005, sides: 5, color: chain)
        Primitives.smoothTube(into: &m, from: bb + Float3(0, -0.105, z), to: cassette + Float3(0.02, -0.09, 0), radius: 0.005, sides: 5, color: chain)
        Primitives.box(into: &m, min: cassette + Float3(-0.02, -0.12, -0.005), max: cassette + Float3(0.03, -0.05, 0.02), color: frameDark, bottom: true)
        // bottle cage + bottle on the down tube
        let dt = Mesh.normalize(headBottom - bb)
        let bottleA = bb + dt * 0.12 + Float3(-dt.y, dt.x, 0) * 0.055
        Primitives.smoothTube(into: &m, from: bottleA, to: bottleA + dt * 0.2, radius: 0.034, sides: 12, color: white)
        Primitives.smoothTube(into: &m, from: bottleA + dt * 0.2, to: bottleA + dt * 0.235, radius: 0.02, endRadius: 0.012, sides: 8, color: accent)
        return m
    }

    /// Wheel centred on the origin in the X/Y plane (axle along Z): tyre,
    /// deep-section carbon rim with a decal, spokes and hub.
    public static func wheel() -> Mesh {
        var m = Mesh()
        let r = AvatarGeometry.wheelRadius
        let segments = 36
        let carbon = Float3(0.09, 0.09, 0.10)
        let decal = Float3(0.85, 0.85, 0.85)
        for k in 0..<segments {
            let a0 = Float(k) / Float(segments) * 2 * .pi, a1 = Float(k + 1) / Float(segments) * 2 * .pi
            let p0 = Float3(cos(a0), sin(a0), 0), p1 = Float3(cos(a1), sin(a1), 0)
            Primitives.smoothTube(into: &m, from: p0 * (r - 0.014), to: p1 * (r - 0.014), radius: 0.0145, sides: 8, color: tyre)
            // deep rim as two quads per side
            let inner: Float = r - 0.075, outer: Float = r - 0.026
            let col = (k % 9 < 3) ? decal : carbon
            for side: Float in [-0.011, 0.011] {
                let q0 = p0 * inner + Float3(0, 0, side), q1 = p1 * inner + Float3(0, 0, side)
                let q2 = p1 * outer + Float3(0, 0, side), q3 = p0 * outer + Float3(0, 0, side)
                if side > 0 { m.addQuad(q0, q1, q2, q3, color: col) } else { m.addQuad(q0, q3, q2, q1, color: col) }
            }
        }
        for k in 0..<20 {
            let a = Float(k) / 20 * 2 * .pi
            let zOff: Float = k % 2 == 0 ? 0.02 : -0.02
            Primitives.tube(into: &m, from: Float3(0, 0, zOff), to: Float3(cos(a), sin(a), 0) * (r - 0.07), radius: 0.0018, sides: 3, color: metal)
        }
        Primitives.smoothTube(into: &m, from: Float3(0, 0, -0.05), to: Float3(0, 0, 0.05), radius: 0.022, sides: 10, color: metal)
        return m
    }

    /// Two crank arms with pedals; rotates about Z at the bottom bracket.
    public static func crank() -> Mesh {
        var m = Mesh()
        let l = AvatarGeometry.crankLength
        for (z, dir) in [(Float(0.08), Float(1)), (Float(-0.08), Float(-1))] {
            let end = Float3(dir * l, 0, z)
            Primitives.smoothTube(into: &m, from: Float3(0, 0, z), to: end, radius: 0.012, endRadius: 0.01, sides: 8, color: frameDark)
            let out: Float = z > 0 ? 1 : -1
            Primitives.box(into: &m, min: end + Float3(-0.045, -0.01, out > 0 ? 0 : -0.07), max: end + Float3(0.045, 0.012, out > 0 ? 0.07 : 0), color: frameDark, bottom: true)
        }
        return m
    }

    /// Torso, head, helmet, glasses and arms (rigid relative to the bike).
    /// The jersey has a white chest band so riders read as kitted out.
    public static func body(jersey: Float3, geometry g: AvatarGeometry) -> Mesh {
        var m = Mesh()
        let hipC = g.hip + Float3(0.02, 0.05, 0), sh = g.shoulder
        let torso = sh - hipC
        func along(_ t: Float) -> Float3 { hipC + torso * t }
        // torso in bands: jersey – white stripe – jersey (smooth, slightly wider at the chest)
        Primitives.smoothTube(into: &m, from: along(0), to: along(0.48), radius: 0.135, endRadius: 0.15, sides: 16, color: jersey)
        Primitives.smoothTube(into: &m, from: along(0.48), to: along(0.6), radius: 0.15, endRadius: 0.152, sides: 16, color: white)
        Primitives.smoothTube(into: &m, from: along(0.6), to: along(1), radius: 0.152, endRadius: 0.14, sides: 16, color: jersey)
        Primitives.smoothSphere(into: &m, center: along(1), radius: 0.14, scale: Float3(1, 0.85, 1.15), color: jersey)
        Primitives.smoothSphere(into: &m, center: hipC, radius: 0.16, scale: Float3(1, 0.8, 1.08), color: shorts)
        // neck, head, helmet, glasses
        let head = sh + Float3(0.14, 0.16, 0)
        Primitives.smoothTube(into: &m, from: sh + Float3(0.03, 0.05, 0), to: head + Float3(-0.03, -0.05, 0), radius: 0.045, sides: 10, color: skin)
        Primitives.smoothSphere(into: &m, center: head, radius: 0.1, scale: Float3(1.0, 1.08, 0.9), color: skin)
        let helmetColor = jersey * 0.35 + Float3(0.6, 0.6, 0.6)
        Primitives.smoothSphere(into: &m, center: head + Float3(-0.03, 0.05, 0), radius: 0.125, scale: Float3(1.3, 0.78, 0.98), color: helmetColor)
        Primitives.smoothTube(into: &m, from: head + Float3(-0.03, 0.06, -0.12), to: head + Float3(-0.03, 0.06, 0.12), radius: 0.012, sides: 6, color: frameDark)
        Primitives.smoothSphere(into: &m, center: head + Float3(0.085, 0.01, 0), radius: 1, scale: Float3(0.035, 0.03, 0.105), color: Float3(0.05, 0.05, 0.06))
        // arms: jersey sleeve → skin forearm → glove on the hoods
        let hand = Float3(0.56, 0.86, 0)
        for z: Float in [-0.17, 0.17] {
            let s = sh + Float3(0, -0.02, z)
            let h = hand + Float3(0, 0, z * 1.2)
            let e = (s + h) / 2 + Float3(-0.05, -0.05, z * 0.12)
            let sleeveEnd = s + (e - s) * 0.75
            Primitives.smoothTube(into: &m, from: s, to: sleeveEnd, radius: 0.052, endRadius: 0.046, sides: 10, color: jersey)
            Primitives.smoothSphere(into: &m, center: s, radius: 0.058, color: jersey)
            Primitives.smoothTube(into: &m, from: sleeveEnd, to: e, radius: 0.04, sides: 10, color: skin, roundEnds: true)
            Primitives.smoothTube(into: &m, from: e, to: h, radius: 0.036, endRadius: 0.03, sides: 10, color: skin)
            Primitives.smoothSphere(into: &m, center: h, radius: 0.042, scale: Float3(1.2, 0.9, 1), color: glove)
        }
        return m
    }

    /// Unit-length limb along +Y (0…1) – scale Y to the bone length.
    /// `bandColor` paints the last part (e.g. white socks on the shin).
    public static func limb(radius: Float, color: Float3, endRadius: Float? = nil, bandColor: Float3? = nil, bandFrom: Float = 0.78) -> Mesh {
        var m = Mesh()
        let r1 = endRadius ?? radius
        if let band = bandColor {
            let rb = radius + (r1 - radius) * bandFrom
            Primitives.smoothTube(into: &m, from: Float3(0, 0, 0), to: Float3(0, bandFrom, 0), radius: radius, endRadius: rb, sides: 12, color: color)
            Primitives.smoothTube(into: &m, from: Float3(0, bandFrom, 0), to: Float3(0, 1, 0), radius: rb * 1.03, endRadius: r1 * 1.03, sides: 12, color: band)
        } else {
            Primitives.smoothTube(into: &m, from: Float3(0, 0, 0), to: Float3(0, 1, 0), radius: radius, endRadius: r1, sides: 12, color: color)
        }
        return m
    }

    /// Ball for knees/ankles so scaled limbs join smoothly.
    public static func joint(radius: Float, color: Float3) -> Mesh {
        var m = Mesh()
        Primitives.smoothSphere(into: &m, center: Float3(), radius: radius, color: color)
        return m
    }

    /// Cycling shoe, toe pointing +X, origin at the cleat.
    public static func shoe() -> Mesh {
        var m = Mesh()
        Primitives.smoothSphere(into: &m, center: Float3(0.05, 0.035, 0), radius: 1, scale: Float3(0.13, 0.045, 0.048), color: AvatarMeshes.shoeWhite)
        Primitives.box(into: &m, min: Float3(-0.07, -0.005, -0.045), max: Float3(0.16, 0.012, 0.045), color: frameDark, bottom: true)
        return m
    }
}
