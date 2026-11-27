import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct ProgressionTests {
    func ride(km: Double, ascent: Double = 0, minutes: Int = 60, routeId: String = "skogsslingan", pb: Bool = false, ftp: Double? = nil, tss: Double = 50) -> RideRecord {
        var s = RideStats()
        s.distance = km * 1000
        s.ascent = ascent
        s.duration = minutes * 60
        s.tss = tss
        let seg = pb ? [SegmentResult(segmentId: "x", name: "x", kind: .climb, seconds: 100, averagePower: 250, isPersonalBest: true)] : []
        return RideRecord(startDate: Date(), routeId: routeId, routeName: routeId, workoutName: nil, riderWeightKg: 75, ftp: 250,
                          elapsedSeconds: minutes * 60, stats: s, segments: seg, ftpEstimate: ftp, samples: [])
    }

    @Test func levelCurve() {
        #expect(Progression.level(forXP: 0) == 1)
        #expect(Progression.level(forXP: 399) == 1)
        #expect(Progression.level(forXP: 400) == 2)
        #expect(Progression.level(forXP: 1200) == 3)
        var p = Progression()
        p.xp = 800
        #expect(abs(p.levelProgress - 0.5) < 1e-9)
    }

    @Test func xpFormula() {
        // 30 km → 300, 400 hm → 40, 60 min → 60, workout bonus 50, one PB 15
        #expect(Progression.xp(for: ride(km: 30, ascent: 400, pb: true), workoutCompleted: true) == 465)
    }

    @Test func achievementsAndUnlocks() {
        var p = Progression()
        let all = ["skogsslingan", "fjallvagen"]
        let u1 = p.apply(ride(km: 30, ascent: 400), workoutCompleted: false, allRouteIds: all)
        #expect(u1.newAchievements == ["first-ride"])
        #expect(u1.levelAfter == 2 && u1.leveledUp)
        let u2 = p.apply(ride(km: 80, ascent: 700, minutes: 150, routeId: "fjallvagen", pb: true, ftp: 260, tss: 140),
                         workoutCompleted: false, allRouteIds: all)
        #expect(Set(u2.newAchievements) == ["km-100", "climb-1000", "long-ride", "ftp-test", "pr", "all-worlds", "tss-100"])
        #expect(u2.newJerseys.contains(4), "level 3 unlocks the orange jersey")
        #expect(p.isJerseyUnlocked(4) && !p.isJerseyUnlocked(10))
        // achievements are only awarded once
        let u3 = p.apply(ride(km: 5), workoutCompleted: false, allRouteIds: all)
        #expect(u3.newAchievements.isEmpty)
        #expect(Progression.jerseyUnlockLevel.count == RiderProfile.jerseyPalette.count)
    }

    @Test func rebuildMatchesIncremental() {
        let rides = [ride(km: 10), ride(km: 20, ascent: 300, pb: true)]
        var p = Progression()
        for r in rides { p.apply(r, workoutCompleted: false, allRouteIds: ["a"]) }
        #expect(Progression.rebuild(from: rides, allRouteIds: ["a"]) == p)
    }

    @Test func codableRoundTrip() throws {
        var p = Progression()
        p.apply(ride(km: 12), workoutCompleted: false, allRouteIds: [])
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(Progression.self, from: data) == p)
    }
}
