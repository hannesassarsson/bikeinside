import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct GroupRaceTests {
    @Test func cheerAndRaceMessagesRoundTrip() {
        let c = Cheer(from: "a", name: "Hannes", text: "👏 Heja!")
        #expect(RealtimeProtocol.decode(RealtimeProtocol.broadcast(topic: "t", event: "cheer", value: c, ref: 2)) == .cheer(c))
        let r = RaceAnnouncement(raceId: "r1", routeId: "skogsslingan", startAt: 1000, distance: 2000, starterName: "H")
        #expect(RealtimeProtocol.decode(RealtimeProtocol.broadcast(topic: "t", event: "race", value: r, ref: 3)) == .race(r))
        let f = RaceFinish(raceId: "r1", id: "a", name: "H", seconds: 200)
        #expect(RealtimeProtocol.decode(RealtimeProtocol.broadcast(topic: "t", event: "finish", value: f, ref: 4)) == .finish(f))
        var bad = r
        bad.distance = 5
        #expect(RealtimeProtocol.decode(RealtimeProtocol.broadcast(topic: "t", event: "race", value: bad, ref: 5)) == .other)
        #expect(Cheer(from: "a", name: "x", text: "   ").sanitized() == nil)
    }

    @Test func raceLifecycle() {
        var t = RaceTracker()
        let r = RaceAnnouncement(raceId: "r1", routeId: "skogsslingan", startAt: 1000, distance: 1000, starterName: "H")
        let otherRoute = t.announce(r, routeId: "fjallvagen", myId: "me")
        #expect(!otherRoute, "other route ignored")
        let accepted = t.announce(r, routeId: "skogsslingan", myId: "me")
        #expect(accepted)
        let duplicate = t.announce(r, routeId: "skogsslingan", myId: "me")
        #expect(!duplicate, "duplicate ignored")
        #expect(t.phase(now: 995.2, distance: 500) == .countdown(secondsLeft: 5))
        let early = t.update(now: 999, distance: 500, myName: "Jag")
        #expect(early == nil)
        _ = t.update(now: 1000, distance: 520, myName: "Jag")   // start line at 520 m
        #expect(t.remaining(distance: 1020) == 500)
        if case .racing(let p, _) = t.phase(now: 1050, distance: 1020) { #expect(abs(p - 0.5) < 1e-9) } else { Issue.record("racing") }
        t.record(RaceFinish(raceId: "r1", id: "friend", name: "Kompis", seconds: 110))
        let mine = t.update(now: 1120, distance: 1525, myName: "Jag")
        #expect(mine?.seconds == 120 && mine?.id == "me")
        #expect(t.phase(now: 1121, distance: 1600) == .finished(seconds: 120, place: 2))
        #expect(t.results.map(\.name) == ["Kompis", "Jag"])
        let again = t.update(now: 1130, distance: 2000, myName: "Jag")
        #expect(again == nil, "only finishes once")
        t.record(RaceFinish(raceId: "other", id: "x", name: "x", seconds: 1))
        #expect(t.results.count == 2, "finishes from other races ignored")
    }
}
