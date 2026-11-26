import Foundation

/// Two-bone inverse kinematics in the bike's side plane, used to animate the
/// rider's legs from hip to pedal.
public enum LegIK {
    /// Knee position for a leg with `upper`/`lower` bone lengths so that the
    /// foot reaches `foot`. The knee bends towards +x (forwards). If the foot
    /// is out of reach the leg is straightened towards it.
    public static func knee(hip: Vec2, foot: Vec2, upper: Double, lower: Double) -> Vec2 {
        let d = foot - hip
        let rawDist = d.length
        let dist = Interp.clamp(rawDist, abs(upper - lower) + 1e-6, upper + lower - 1e-6)
        let dir = rawDist > 1e-9 ? d / rawDist : Vec2(0, -1)
        // distance from hip along dir to the foot of the knee's perpendicular
        let a = (upper * upper - lower * lower + dist * dist) / (2 * dist)
        let h = max(upper * upper - a * a, 0).squareRoot()
        let base = hip + dir * a
        // two candidates; choose the one in front (+x)
        let perp = Vec2(-dir.y, dir.x)
        let k1 = base + perp * h, k2 = base - perp * h
        return k1.x >= k2.x ? k1 : k2
    }

    /// Pedal position for a crank angle (radians, 0 = forward, counter-clockwise
    /// seen from the right side, i.e. the rider pedals with decreasing angle).
    public static func pedal(bottomBracket: Vec2, crankLength: Double, angle: Double) -> Vec2 {
        bottomBracket + Vec2(cos(angle), sin(angle)) * crankLength
    }
}
