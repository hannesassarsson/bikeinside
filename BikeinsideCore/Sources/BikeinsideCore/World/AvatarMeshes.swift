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

    /// Frame, fork, saddle, bars and chainring – everything rigid on the bike.
    public static func bike(accent: Float3) -> Mesh {
        var m = Mesh()
        let rear = AvatarGeometry.rearAxle, front = AvatarGeometry.frontAxle
        let bb = AvatarGeometry.bottomBracket
        let seatTop = Float3(-0.15, 0.80, 0)
        let headTop = Float3(0.40, 0.78, 0)
        let headBottom = Float3(0.44, 0.62, 0)
        Primitives.tube(into: &m, from: bb, to: seatTop, radius: 0.019, sides: 8, color: accent)
        Primitives.tube(into: &m, from: seatTop, to: headTop, radius: 0.018, sides: 8, color: accent)
        Primitives.tube(into: &m, from: bb, to: headBottom, radius: 0.023, sides: 8, color: accent)
        Primitives.tube(into: &m, from: headBottom, to: headTop, radius: 0.021, sides: 8, color: frameDark)
        for z: Float in [-0.05, 0.05] {
            let o = Float3(0, 0, z)
            Primitives.tube(into: &m, from: bb + o * 0.6, to: rear + o, radius: 0.011, sides: 6, color: frameDark)
            Primitives.tube(into: &m, from: seatTop + o * 0.4, to: rear + o, radius: 0.010, sides: 6, color: frameDark)
            Primitives.tube(into: &m, from: headBottom + o * 0.4, to: front + o, radius: 0.012, sides: 6, color: frameDark)
        }
        // seatpost + saddle
        let saddle = Float3(-0.18, 0.86, 0)
        Primitives.tube(into: &m, from: seatTop, to: saddle, radius: 0.012, sides: 6, color: frameDark)
        Primitives.box(into: &m, min: saddle + Float3(-0.14, 0, -0.06), max: saddle + Float3(0.12, 0.035, 0.06), color: shorts, bottom: true)
        // stem + bars with drops
        let bar = Float3(0.50, 0.84, 0)
        Primitives.tube(into: &m, from: headTop, to: bar, radius: 0.014, sides: 6, color: frameDark)
        Primitives.tube(into: &m, from: bar + Float3(0, 0, -0.21), to: bar + Float3(0, 0, 0.21), radius: 0.013, sides: 6, color: frameDark)
        for z: Float in [-0.21, 0.21] {
            Primitives.tube(into: &m, from: bar + Float3(0, 0, z), to: bar + Float3(0.09, -0.13, z), radius: 0.013, sides: 6, color: frameDark, roundEnds: true)
        }
        // chainring disc (right side)
        for k in 0..<16 {
            let a0 = Float(k) / 16 * 2 * .pi, a1 = Float(k + 1) / 16 * 2 * .pi
            let c = bb + Float3(0, 0, 0.06)
            let p0 = c + Float3(cos(a0), sin(a0), 0) * 0.1, p1 = c + Float3(cos(a1), sin(a1), 0) * 0.1
            m.addTriangle(c, p0, p1, color: metal)
            m.addTriangle(c, p1, p0, color: metal)
        }
        return m
    }

    /// Wheel centred on the origin in the X/Y plane (axle along Z).
    public static func wheel() -> Mesh {
        var m = Mesh()
        let r = AvatarGeometry.wheelRadius
        let segments = 28
        for k in 0..<segments {
            let a0 = Float(k) / Float(segments) * 2 * .pi, a1 = Float(k + 1) / Float(segments) * 2 * .pi
            let p0 = Float3(cos(a0), sin(a0), 0), p1 = Float3(cos(a1), sin(a1), 0)
            Primitives.tube(into: &m, from: p0 * (r - 0.016), to: p1 * (r - 0.016), radius: 0.016, sides: 6, color: tyre)
            Primitives.tube(into: &m, from: p0 * (r - 0.04), to: p1 * (r - 0.04), radius: 0.008, sides: 4, color: metal)
        }
        for k in 0..<8 { // spokes
            let a = Float(k) / 8 * 2 * .pi
            Primitives.tube(into: &m, from: Float3(0, 0, 0), to: Float3(cos(a), sin(a), 0) * (r - 0.04), radius: 0.003, sides: 3, color: metal)
        }
        Primitives.tube(into: &m, from: Float3(0, 0, -0.05), to: Float3(0, 0, 0.05), radius: 0.025, sides: 8, color: frameDark)
        return m
    }

    /// Two crank arms with pedals; rotates about Z at the bottom bracket.
    public static func crank() -> Mesh {
        var m = Mesh()
        let l = AvatarGeometry.crankLength
        for (z, dir) in [(Float(0.08), Float(1)), (Float(-0.08), Float(-1))] {
            let end = Float3(dir * l, 0, z)
            Primitives.tube(into: &m, from: Float3(0, 0, z), to: end, radius: 0.012, sides: 6, color: frameDark)
            Primitives.box(into: &m, min: end + Float3(-0.045, -0.01, -0.04 * (z > 0 ? -0.2 : 1)), max: end + Float3(0.045, 0.01, 0.04 * (z > 0 ? 1 : -0.2)), color: frameDark, bottom: true)
        }
        return m
    }

    /// Torso, head, helmet and arms (rigid relative to the bike).
    public static func body(jersey: Float3, geometry g: AvatarGeometry) -> Mesh {
        var m = Mesh()
        let hipC = g.hip, sh = g.shoulder
        // torso as a fat tube with rounded ends, slightly wider at the shoulders
        Primitives.tube(into: &m, from: hipC + Float3(0.02, 0.04, 0), to: sh, radius: 0.15, sides: 10, color: jersey, roundEnds: true)
        // shorts over the hips
        Primitives.blob(into: &m, center: hipC + Float3(0.0, 0.02, 0), radius: Float3(0.16, 0.12, 0.17), color: shorts, subdivide: true)
        // head + helmet
        let head = sh + Float3(0.13, 0.17, 0)
        Primitives.blob(into: &m, center: head, radius: Float3(0.095, 0.105, 0.09), color: skin, subdivide: true)
        let helmet = jersey * 0.6 + Float3(0.4, 0.4, 0.4)
        Primitives.blob(into: &m, center: head + Float3(-0.025, 0.045, 0), radius: Float3(0.155, 0.10, 0.12), color: helmet, subdivide: true)
        // arms to the hoods
        let hand = Float3(0.53, 0.86, 0)
        for z: Float in [-0.17, 0.17] {
            let s = sh + Float3(0, -0.03, z)
            let h = hand + Float3(0, 0, z * 1.18)
            let e = (s + h) / 2 + Float3(-0.05, -0.04, z * 0.12)
            Primitives.tube(into: &m, from: s, to: e, radius: 0.047, sides: 8, color: jersey, roundEnds: true)
            Primitives.tube(into: &m, from: e, to: h, radius: 0.037, sides: 8, color: skin, roundEnds: true)
            Primitives.blob(into: &m, center: h, radius: Float3(0.04, 0.04, 0.04), color: shorts)
        }
        return m
    }

    /// Unit-length limb along +Y (0…1) – scale Y to the bone length.
    public static func limb(radius: Float, color: Float3) -> Mesh {
        var m = Mesh()
        Primitives.tube(into: &m, from: Float3(0, 0, 0), to: Float3(0, 1, 0), radius: radius, sides: 8, color: color)
        return m
    }

    /// Ball for knees/ankles so scaled limbs join smoothly.
    public static func joint(radius: Float, color: Float3) -> Mesh {
        var m = Mesh()
        Primitives.blob(into: &m, center: Float3(), radius: Float3(repeating: radius), color: color)
        return m
    }

    /// Cycling shoe, toe pointing +X, origin at the cleat.
    public static func shoe() -> Mesh {
        var m = Mesh()
        Primitives.box(into: &m, min: Float3(-0.07, 0.0, -0.045), max: Float3(0.17, 0.07, 0.045), color: AvatarMeshes.shoeWhite, bottom: true)
        return m
    }
}
