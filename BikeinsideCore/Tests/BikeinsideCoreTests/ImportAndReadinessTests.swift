import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct GPXTests {
    /// A ~6 km out-and-up line north of Stockholm with a 60 m climb in the middle and GPS noise.
    func gpx(loop: Bool) -> Data {
        var s = "<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"test\"><trk><name>Min runda</name><trkseg>"
        let n = 600
        var rng = SeededRandom(seed: 3)
        for i in 0...n {
            let t = Double(i) / Double(n)
            let lat: Double, lon: Double
            if loop {
                let a = t * 2 * .pi
                lat = 59.40 + 0.009 * sin(a)
                lon = 18.00 + 0.017 * cos(a)
            } else {
                lat = 59.40 + 0.05 * t
                lon = 18.00 + 0.01 * sin(t * 6)
            }
            let ele = 20 + 60 * exp(-pow((t - 0.5) / 0.12, 2)) + rng.range(-1.5, 1.5)
            s += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(ele)</ele><time>2026-01-01T10:00:00Z</time></trkpt>"
        }
        s += "</trkseg></trk></gpx>"
        return Data(s.utf8)
    }

    @Test func parsesTrackAndBuildsOpenRoute() throws {
        let parsed = try GPXImport.parse(gpx(loop: false), fallbackName: "fil")
        #expect(parsed.name == "Min runda" && parsed.points.count == 601)
        let imp = ImportedRoute(id: "gpx-1", name: parsed.name, theme: .forest, points: parsed.points)
        let r = try GPXImport.buildRoute(imp)
        print("[gpx] open \(Int(r.length)) m, +\(Int(r.totalAscent)) m, max \(r.maxGrade), segs \(r.segments.count)")
        #expect(!r.isLoop)
        #expect(r.length > 5000 && r.length < 6500)
        #expect(abs(r.spacing - 2) < 0.05)
        #expect(r.totalAscent > 45 && r.totalAscent < 90, "noise smoothed out")
        #expect(r.maxGrade < 0.19)
        #expect(r.segments.contains { $0.kind == .climb })
        // sampling past the end clamps
        #expect((r.sample(at: r.length + 500).position - r.points.last!).length < 1e-6)
    }

    @Test func closedTrackBecomesLoopAndWorldBuilds() throws {
        let parsed = try GPXImport.parse(gpx(loop: true), fallbackName: "fil")
        let r = try GPXImport.buildRoute(ImportedRoute(id: "gpx-2", name: "x", theme: .mountain, points: parsed.points))
        #expect(r.isLoop)
        let w = WorldBuilder.build(route: r)
        #expect(!w.road.isEmpty && w.stats.trees > 100)
        let t = w.terrain
        for i in stride(from: 0, to: r.points.count, by: 200) {
            let p = r.points[i]
            #expect(t.height(x: p.x, z: p.z) < p.y + 0.06)
        }
    }

    @Test func rejectsBadFiles() {
        #expect(throws: GPXImport.ImportError.noPoints) { try GPXImport.parse(Data("<gpx></gpx>".utf8), fallbackName: "x") }
        let tiny = ImportedRoute(id: "t", name: "t", theme: .forest, points: [
            .init(lat: 59, lon: 18, ele: 1), .init(lat: 59.0001, lon: 18, ele: 1),
        ])
        #expect(throws: GPXImport.ImportError.tooShort) { try GPXImport.buildRoute(tiny) }
    }

    @Test func openRouteFinishes() throws {
        let parsed = try GPXImport.parse(gpx(loop: false), fallbackName: "fil")
        let r = try GPXImport.buildRoute(ImportedRoute(id: "gpx-3", name: "x", theme: .forest, points: parsed.points))
        let e = RideEngine(config: .init(route: r, rider: .default, autoPause: false))
        var events: [RideEvent] = []
        var guardN = 0
        while !e.reachedEnd && guardN < 100_000 { e.tick(dt: 0.25, inputs: RideInputs(power: 300)); events += e.drainEvents(); guardN += 1 }
        #expect(e.reachedEnd)
        #expect(abs(e.distance - r.length) < 1e-6 && e.speed == 0)
        #expect(events.filter { $0 == .routeFinished }.count == 1)
        e.tick(dt: 0.25, inputs: RideInputs(power: 300))
        #expect(e.distance == r.length)
    }
}

@Suite struct ReadinessTests {
    let good = HealthDay(day: "2026-11-27", sleepHours: 8, sleepScore: 85, hrvLastNight: 62, hrvBaselineLow: 50, hrvBaselineHigh: 70,
                         restingHR: 48, restingHR7dAvg: 49, bodyBatteryHigh: 90, trainingReadiness: 82)
    let bad = HealthDay(day: "2026-11-27", sleepHours: 4.8, hrvLastNight: 38, hrvBaselineLow: 50, hrvBaselineHigh: 70,
                        restingHR: 57, restingHR7dAvg: 49, bodyBatteryHigh: 35, trainingReadiness: 22)

    @Test func goodDayRidesAsPlanned() throws {
        let r = try #require(Readiness.assess(days: [good], checkIn: nil, today: "2026-11-27"))
        #expect(r.score >= 75 && r.advice == .asPlanned)
        #expect(r.alternative(for: WorkoutLibrary.vo2max5x3, ftp: 250) == nil)
    }

    @Test func badDaySwapsHardWorkout() throws {
        let r = try #require(Readiness.assess(days: [bad], checkIn: CheckIn(legs: 2, energy: 2), today: "2026-11-27"))
        #expect(r.score < 35 && r.advice == .rest)
        #expect(r.alternative(for: WorkoutLibrary.vo2max5x3, ftp: 250)?.id == WorkoutLibrary.recoverySpin.id)
        #expect(r.reasons.contains { $0.contains("HRV") } && r.reasons.contains { $0.contains("sömn") })
    }

    @Test func middlingDayReducesIntensity() throws {
        var d = good
        d.trainingReadiness = 60
        d.hrvLastNight = 52
        d.sleepHours = 6.5
        let r = try #require(Readiness.assess(days: [d], checkIn: nil, today: "2026-11-27"))
        #expect(r.advice == .reduce(0.92) || r.advice == .easier, "\(r.score)")
        #expect(Readiness.assess(days: [], checkIn: nil, today: "x") == nil)
        // check-in alone works
        #expect(Readiness.assess(days: [], checkIn: CheckIn(legs: 5, energy: 5), today: "x")?.advice == .asPlanned)
    }

    @Test func decodesSupabaseJSON() throws {
        let json = #"[{"day":"2026-11-27","sleep_hours":7.4,"hrv_last_night":55,"hrv_baseline_low":48,"hrv_baseline_high":66,"resting_hr":50,"resting_hr_7d_avg":51,"training_readiness":71,"hrv_status":"BALANCED","sleep_score":null}]"#
        let days = try JSONDecoder().decode([HealthDay].self, from: Data(json.utf8))
        #expect(days[0].trainingReadiness == 71 && days[0].sleepScore == nil)
    }
}

@Suite struct MrcExportTests {
    @Test func exportRoundTrips() throws {
        let w = WorkoutLibrary.sweetSpot3x10
        let text = WorkoutFileParser.mrc(w, ftp: 250)
        let back = try WorkoutFileParser.parse(text: text, fallbackName: "x")
        #expect(back.name == w.name)
        #expect(abs(back.duration - w.duration) < 1)
        #expect(abs(back.estimatedTSS(ftp: 250) - w.estimatedTSS(ftp: 250)) < 0.5)
    }
}
