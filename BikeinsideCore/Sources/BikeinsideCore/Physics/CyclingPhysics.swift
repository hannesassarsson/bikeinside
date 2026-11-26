import Foundation

/// Parameters for the rider+bike system used by the physics integrator.
public struct PhysicsParameters: Sendable, Equatable {
    /// Rider + bike mass in kg.
    public var totalMass: Double
    /// Drag area in m².
    public var cda: Double
    /// Rolling resistance coefficient.
    public var crr: Double
    /// Fraction of pedal power that reaches the rear wheel.
    public var drivetrainEfficiency: Double
    /// Extra "virtual" mass representing wheel rotational inertia (I/r²).
    public var rotatingMassEquivalent: Double
    /// Air density in kg/m³.
    public var airDensity: Double

    public init(
        totalMass: Double,
        cda: Double,
        crr: Double = 0.004,
        drivetrainEfficiency: Double = 0.975,
        rotatingMassEquivalent: Double = 1.4,
        airDensity: Double = 1.225
    ) {
        self.totalMass = totalMass
        self.cda = cda
        self.crr = crr
        self.drivetrainEfficiency = drivetrainEfficiency
        self.rotatingMassEquivalent = rotatingMassEquivalent
        self.airDensity = airDensity
    }

    public init(rider: RiderProfile, crr: Double = 0.004) {
        self.init(totalMass: rider.weightKg + rider.bikeWeightKg, cda: rider.cda, crr: crr)
    }
}

/// Classic road-cycling force balance:
/// drive = gravity + rolling resistance + aerodynamic drag + m·a
public enum CyclingPhysics {
    public static let g = 9.80665

    /// Barometric air density for an altitude (m) and temperature (°C).
    public static func airDensity(altitude: Double, temperatureC: Double = 15) -> Double {
        let t = temperatureC + 273.15
        let p = 101_325 * pow(1 - 2.25577e-5 * max(altitude, -400), 5.25588)
        return p / (287.05 * t)
    }

    /// Sum of resistive forces in newtons (positive = opposing motion).
    /// - Parameters:
    ///   - grade: rise/run (0.05 = 5 %).
    ///   - draftFactor: multiplier on aerodynamic drag (1 = no draft).
    ///   - headwind: wind speed against the rider in m/s.
    public static func resistiveForce(
        speed: Double, grade: Double, params: PhysicsParameters,
        draftFactor: Double = 1, headwind: Double = 0
    ) -> Double {
        let theta = atan(grade)
        let m = params.totalMass
        let gravity = m * g * sin(theta)
        let rolling = m * g * cos(theta) * params.crr
        let vAir = speed + headwind
        let aero = 0.5 * params.airDensity * params.cda * draftFactor * vAir * abs(vAir)
        return gravity + rolling + aero
    }

    /// Advance speed by `dt` seconds given pedal power. Integrates in small
    /// sub-steps so behaviour is independent of frame rate.
    public static func step(
        speed: Double, power: Double, grade: Double, dt: Double,
        params: PhysicsParameters, draftFactor: Double = 1, headwind: Double = 0
    ) -> Double {
        guard dt > 0 else { return speed }
        let maxStep = 0.02
        let n = max(1, Int((dt / maxStep).rounded(.up)))
        let h = dt / Double(n)
        let wheelPower = max(power, 0) * params.drivetrainEfficiency
        let mEff = params.totalMass + params.rotatingMassEquivalent
        var v = max(speed, 0)
        for _ in 0..<n {
            // Below ~1 m/s, treat drive as force-limited so a standing start
            // doesn't divide by zero (P/v → ∞).
            let drive = wheelPower / max(v, 1.0)
            var resist = resistiveForce(speed: v, grade: grade, params: params, draftFactor: draftFactor, headwind: headwind)
            if v < 0.05 {
                // At standstill rolling resistance can only hold you still,
                // never push you backwards.
                let theta = atan(grade)
                let rolling = params.totalMass * g * cos(theta) * params.crr
                let gravity = params.totalMass * g * sin(theta)
                if drive - gravity <= rolling && drive - gravity >= -rolling {
                    resist = drive // static: no motion
                }
            }
            let a = (drive - resist) / mEff
            v = max(0, v + a * h)
        }
        return v
    }

    /// Pedal power required to hold `speed` steadily.
    public static func requiredPower(
        speed: Double, grade: Double, params: PhysicsParameters,
        draftFactor: Double = 1, headwind: Double = 0
    ) -> Double {
        let f = resistiveForce(speed: speed, grade: grade, params: params, draftFactor: draftFactor, headwind: headwind)
        return max(0, f * speed / params.drivetrainEfficiency)
    }

    /// Steady-state speed for a constant power, found by bisection.
    /// Unique for P ≥ 0 because F(v)·v is eventually increasing.
    public static func steadyStateSpeed(
        power: Double, grade: Double, params: PhysicsParameters,
        draftFactor: Double = 1, headwind: Double = 0
    ) -> Double {
        let target = max(power, 0) * params.drivetrainEfficiency
        func excess(_ v: Double) -> Double {
            target - resistiveForce(speed: v, grade: grade, params: params, draftFactor: draftFactor, headwind: headwind) * v
        }
        var lo = 0.0, hi = 50.0
        if excess(hi) > 0 { return hi }
        // If excess is negative everywhere just above 0 the rider stands still.
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if excess(mid) > 0 { lo = mid } else { hi = mid }
        }
        // P = 0 on flat/uphill: resistance at v>0 makes excess < 0 → converges to 0.
        return (lo + hi) / 2
    }
}

/// Aerodynamic benefit of riding behind someone.
public enum Drafting {
    /// Drag multiplier for a rider `gap` metres behind the wheel in front.
    /// ≈ 0.65 when glued to the wheel, fading to 1.0 beyond ~15 m.
    public static func dragFactor(gap: Double) -> Double {
        guard gap > 0.2, gap < 20 else { return 1 }
        let saving = 0.35 * exp(-max(gap - 0.6, 0) / 4.0)
        return 1 - saving
    }

    /// Best drag factor given the route positions of other riders.
    /// - Parameter loopLength: route length when riders lap a loop (gaps wrap).
    public static func dragFactor(position: Double, others: [Double], loopLength: Double?) -> Double {
        var best = 1.0
        for o in others {
            var gap = o - position
            if let L = loopLength, L > 0 {
                gap = gap.truncatingRemainder(dividingBy: L)
                if gap < 0 { gap += L }
            }
            best = min(best, dragFactor(gap: gap))
        }
        return best
    }
}
