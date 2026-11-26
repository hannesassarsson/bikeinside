import Testing
@testable import BikeinsideCore

@Suite struct PhysicsTests {
    let params = PhysicsParameters(totalMass: 83, cda: 0.30, crr: 0.004)

    @Test func flatSteadyStateAt200W() {
        let v = CyclingPhysics.steadyStateSpeed(power: 200, grade: 0, params: params)
        // ≈ 34.6 km/h by hand calculation
        #expect(abs(v * 3.6 - 34.6) < 0.5)
        // and required power round-trips
        #expect(abs(CyclingPhysics.requiredPower(speed: v, grade: 0, params: params) - 200) < 0.01)
    }

    @Test func climbingIsSlow() {
        let v = CyclingPhysics.steadyStateSpeed(power: 250, grade: 0.07, params: params) * 3.6
        #expect(v > 11 && v < 15)
    }

    @Test func coastingDownhillReachesTerminalSpeed() {
        let v = CyclingPhysics.steadyStateSpeed(power: 0, grade: -0.06, params: params) * 3.6
        #expect(v > 50 && v < 70)
    }

    @Test func zeroPowerOnFlatStandsStill() {
        #expect(CyclingPhysics.steadyStateSpeed(power: 0, grade: 0, params: params) < 0.01)
        #expect(CyclingPhysics.step(speed: 0, power: 0, grade: 0.05, dt: 1, params: params) == 0)
    }

    @Test func integratorConvergesToSteadyState() {
        var v = 0.0
        for _ in 0..<(60 * 120) { v = CyclingPhysics.step(speed: v, power: 200, grade: 0, dt: 1.0 / 60, params: params) }
        let expected = CyclingPhysics.steadyStateSpeed(power: 200, grade: 0, params: params)
        #expect(abs(v - expected) < 0.05)
    }

    @Test func integratorIsFrameRateIndependent() {
        var a = 5.0, b = 5.0
        for _ in 0..<600 { a = CyclingPhysics.step(speed: a, power: 300, grade: 0.03, dt: 1.0 / 60, params: params) }
        for _ in 0..<100 { b = CyclingPhysics.step(speed: b, power: 300, grade: 0.03, dt: 0.1, params: params) }
        #expect(abs(a - b) < 0.02)
    }

    @Test func standingStartAccelerates() {
        let v = CyclingPhysics.step(speed: 0, power: 300, grade: 0, dt: 1, params: params)
        #expect(v > 1 && v < 5)
    }

    @Test func draftingSavesPower() {
        #expect(Drafting.dragFactor(gap: 1.0) < 0.7)
        #expect(Drafting.dragFactor(gap: 5.0) > Drafting.dragFactor(gap: 1.0))
        #expect(Drafting.dragFactor(gap: 30) == 1)
        #expect(Drafting.dragFactor(gap: -2) == 1) // rider behind you doesn't help
        // wraps on a loop: rider at 2 m is 3 m ahead of rider at 9999 on a 10 km loop
        let f = Drafting.dragFactor(position: 9999, others: [2], loopLength: 10_000)
        #expect(f < 0.85)
        let vDraft = CyclingPhysics.steadyStateSpeed(power: 200, grade: 0, params: params, draftFactor: 0.7)
        #expect(vDraft > CyclingPhysics.steadyStateSpeed(power: 200, grade: 0, params: params) + 1)
    }

    @Test func airDensityDropsWithAltitude() {
        let sea = CyclingPhysics.airDensity(altitude: 0)
        #expect(abs(sea - 1.225) < 0.01)
        #expect(CyclingPhysics.airDensity(altitude: 2000) < sea * 0.85)
    }

    @Test func riderProfileDerivedValues() {
        let p = RiderProfile(weightKg: 75, heightCm: 180, ftp: 250)
        #expect(abs(p.cda - 0.30) < 0.02)
        #expect(abs(p.wattsPerKgAtFTP - 3.333) < 0.01)
        let bad = RiderProfile(name: "  ", weightKg: .nan, ftp: 5000).sanitized()
        #expect(bad.name == "Cyklist" && bad.weightKg == 75 && bad.ftp == 600)
    }

    @Test func powerZones() {
        #expect(PowerZone.zone(power: 100, ftp: 250) == .z1)
        #expect(PowerZone.zone(power: 250, ftp: 250) == .z4)
        #expect(PowerZone.zone(power: 500, ftp: 250) == .z7)
    }
}

@Suite struct MathTests {
    @Test func noiseIsDeterministicAndBounded() {
        let n = ValueNoise2D(seed: 42)
        var lo = 1.0, hi = -1.0
        for i in 0..<2000 {
            let v = n.fbm(Double(i) * 0.137, Double(i) * 0.071)
            lo = min(lo, v)
            hi = max(hi, v)
        }
        #expect(lo >= -1 && hi <= 1 && hi - lo > 0.5)
        #expect(n.sample(3.3, 4.4) == ValueNoise2D(seed: 42).sample(3.3, 4.4))
        #expect(n.sample(3.3, 4.4) != ValueNoise2D(seed: 43).sample(3.3, 4.4))
    }

    @Test func seededRandomRepeats() {
        var a = SeededRandom(seed: 7), b = SeededRandom(seed: 7)
        for _ in 0..<10 { #expect(a.next() == b.next()) }
        var c = SeededRandom(seed: 1)
        for _ in 0..<1000 {
            let u = c.unit()
            #expect(u >= 0 && u < 1)
        }
    }

    @Test func angleDelta() {
        #expect(abs(Interp.angleDelta(3.0, -3.0) - (2 * .pi - 6)) < 1e-9)
    }
}
