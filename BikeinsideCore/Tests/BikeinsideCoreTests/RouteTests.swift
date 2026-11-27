import Testing
@testable import BikeinsideCore

@Suite struct RouteTests {
    @Test(arguments: RouteLibrary.all.map(\.id))
    func builtInRoutesAreRideable(id: String) throws {
        let bp = try #require(RouteLibrary.blueprint(id: id))
        let r = RouteBuilder.build(bp)
        print("[route] \(r.name): \(Int(r.length)) m, +\(Int(r.totalAscent)) m, maxGrade \(String(format: "%.1f", r.maxGrade * 100))%, minGrade \(String(format: "%.1f", (r.grades.min() ?? 0) * 100))%, segments \(r.segments.map { "\($0.name) \(Int($0.length))m \(String(format: "%.1f", r.averageGrade(from: $0.startDistance, to: $0.endDistance) * 100))%" })")
        #expect(r.length > 5_000 && r.length < 25_000)
        #expect(abs(r.spacing - 2) < 0.05)
        #expect(r.maxGrade < 0.12)
        #expect((r.grades.min() ?? 0) > -0.12)
        // headings are unit vectors and consecutive headings don't jump (no kinks)
        for i in 0..<r.headings.count {
            #expect(abs(r.headings[i].length - 1) < 1e-6)
            let j = (i + 1) % r.headings.count
            #expect(r.headings[i].dot(r.headings[j]) > 0.995)
        }
        // spacing between consecutive points is uniform (horizontal)
        for i in stride(from: 0, to: r.points.count, by: 97) {
            let j = (i + 1) % r.points.count
            #expect(abs((r.points[j].xz - r.points[i].xz).length - r.spacing) < 0.05)
        }
        if let w = r.waterLevel { #expect(r.minElevation >= w + 2 - 1e-9) }
        #expect(r.segments.contains { $0.kind == .climb })
    }

    @Test func sampleWrapsOnLoop() {
        let r = RouteBuilder.build(RouteLibrary.skogsslingan)
        let a = r.sample(at: 100)
        let b = r.sample(at: 100 + r.length)
        let c = r.sample(at: 100 - r.length)
        #expect((a.position - b.position).length < 1e-6)
        #expect((a.position - c.position).length < 1e-6)
        // the seam between the last and first point is continuous
        let s1 = r.sample(at: r.length - 0.01), s2 = r.sample(at: 0.01)
        #expect((s1.position - s2.position).length < 0.1)
    }

    @Test func monotoneCubicHitsKeysWithoutOvershoot() {
        let keys: [RouteBlueprint.ElevationKey] = [.init(0, 10), .init(0.3, 50), .init(0.6, 20), .init(0.8, 20)]
        #expect(abs(RouteBuilder.periodicMonotoneCubic(keys, t: 0.3) - 50) < 1e-9)
        #expect(abs(RouteBuilder.periodicMonotoneCubic(keys, t: 0) - 10) < 1e-9)
        for k in 0..<1000 {
            let v = RouteBuilder.periodicMonotoneCubic(keys, t: Double(k) / 1000)
            #expect(v >= 10 - 1e-9 && v <= 50 + 1e-9)
        }
        // flat between equal keys
        #expect(abs(RouteBuilder.periodicMonotoneCubic(keys, t: 0.7) - 20) < 1e-9)
    }

    @Test func climbDetectionFindsTheBigClimb() {
        let r = RouteBuilder.build(RouteLibrary.fjallvagen)
        let climb = r.segments.first { $0.kind == .climb }!
        #expect(climb.name == "Fjällbacken")
        let gain = r.sample(at: climb.endDistance).elevation - r.sample(at: climb.startDistance).elevation
        #expect(gain > 200)
    }
}

@Suite struct ReverseRouteTests {
    @Test func reversedRouteHasSameLengthStartAndMirroredProfile() throws {
        let fwd = RouteBuilder.build(try #require(RouteLibrary.blueprint(id: "fjallvagen")))
        let rev = RouteBuilder.build(try #require(RouteLibrary.blueprint(id: "fjallvagen-rev")))
        #expect(rev.id == "fjallvagen-rev" && rev.name.hasSuffix("baklänges"))
        #expect(abs(rev.length - fwd.length) / fwd.length < 0.002)
        #expect((rev.points[0].xz - fwd.points[0].xz).length < 1)
        // heading at the start is (roughly) opposite
        #expect(rev.headings[0].dot(fwd.headings[0]) < -0.9)
        // elevation at d on the reversed route equals elevation at L-d forwards
        for d in stride(from: 500.0, to: fwd.length - 500, by: 900) {
            #expect(abs(rev.sample(at: d).elevation - fwd.sample(at: fwd.length - d).elevation) < 6)
        }
        // the big climb becomes a descent: reversed route has its climb elsewhere
        #expect(rev.segments.contains { $0.kind == .climb })
    }
}
