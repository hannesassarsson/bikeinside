import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct GhostTests {
    @Test func trackInterpolatesBothWays() {
        let g = GhostTrack(routeId: "r", lapSeconds: 40, step: 10, times: [0, 10, 20, 30, 40])
        #expect(g.time(atDistance: 15) == 15)
        #expect(g.distance(atTime: 25) == 25)
        #expect(g.distance(atTime: 100) == 40)
        #expect(g.time(atDistance: 1000) == 40)
        #expect(g.distance(atTime: -1) == 0)
    }

    @Test func recorderInterpolatesMarks() {
        var r = LapTraceRecorder(step: 10)
        r.add(lapTime: 1, lapDistance: 5)
        r.add(lapTime: 3, lapDistance: 25)
        // marks 10 and 20 crossed between t=1 (5 m) and t=3 (25 m) → 1.5 s and 2.5 s
        #expect(r.times == [0, 1.5, 2.5])
    }

    @Test func lapProducesGhostAndRacingItWorks() {
        let route = RouteBuilder.build(RouteLibrary.skogsslingan)
        let first = RideEngine(config: .init(route: route, rider: .default, autoPause: false))
        while first.lapCount < 1 { first.tick(dt: 0.25, inputs: RideInputs(power: 200)) }
        let ghost = try! #require(first.bestLap(beating: nil))
        #expect(ghost.routeId == route.id)
        #expect(abs(ghost.lapSeconds - first.timerTime) < 1)
        #expect(ghost.times.count == Int(route.length / 10) + 1)
        #expect(zip(ghost.times, ghost.times.dropFirst()).allSatisfy { $0 <= $1 }, "monotone")

        // Racing the ghost harder → we pull ahead; ghost gap positive.
        let second = RideEngine(config: .init(route: route, rider: .default, autoPause: false, ghost: ghost))
        for _ in 0..<(4 * 300) { second.tick(dt: 0.25, inputs: RideInputs(power: 260)) }
        #expect((second.ghostGapSeconds ?? 0) > 5)
        #expect((second.ghostDistance ?? .infinity) < second.distance)
        // Same power → roughly level with the ghost.
        let third = RideEngine(config: .init(route: route, rider: .default, autoPause: false, ghost: ghost))
        for _ in 0..<(4 * 300) { third.tick(dt: 0.25, inputs: RideInputs(power: 200)) }
        #expect(abs(third.ghostGapSeconds ?? 99) < 1.5)
        // Slower lap does not replace the ghost.
        #expect(first.bestLap(beating: ghost) == nil)
        // No ghost on another route.
        let other = RideEngine(config: .init(route: RouteBuilder.build(RouteLibrary.sjorundan), rider: .default, ghost: ghost))
        #expect(other.ghostDistance == nil)
    }
}
