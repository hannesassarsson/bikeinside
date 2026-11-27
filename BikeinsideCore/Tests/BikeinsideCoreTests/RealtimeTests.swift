import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct RealtimeTests {
    let state = RemoteRiderState(id: "abc", name: "Hannes", jersey: 2, heightCm: 182, routeId: "skogsslingan",
                                 distance: 1234.5, speed: 9.5, power: 240, wattsPerKg: 3.2, cadence: 88)

    @Test func topicAndURL() {
        #expect(RealtimeProtocol.topic(routeId: "fjallvagen", room: "Klubben 1!") == "realtime:bikeinside:fjallvagen:klubben1")
        #expect(RealtimeProtocol.topic(routeId: "x", room: "") == "realtime:bikeinside:x:alla")
        let url = RealtimeProtocol.websocketURL(projectURL: "https://abc.supabase.co", apiKey: "k")
        #expect(url?.absoluteString == "wss://abc.supabase.co/realtime/v1/websocket?apikey=k&vsn=1.0.0")
    }

    @Test func outgoingMessagesMatchPhoenixFormat() throws {
        let join = try JSONSerialization.jsonObject(with: Data(RealtimeProtocol.join(topic: "realtime:t", presenceKey: "abc", ref: 1).utf8)) as! [String: Any]
        #expect(join["event"] as? String == "phx_join" && join["ref"] as? String == "1")
        let cfg = (join["payload"] as! [String: Any])["config"] as! [String: Any]
        #expect((cfg["presence"] as! [String: Any])["key"] as? String == "abc")
        let b = try JSONSerialization.jsonObject(with: Data(RealtimeProtocol.broadcast(topic: "realtime:t", state: state, ref: 5).utf8)) as! [String: Any]
        let p = b["payload"] as! [String: Any]
        #expect(b["event"] as? String == "broadcast" && p["type"] as? String == "broadcast" && p["event"] as? String == "state")
        #expect((p["payload"] as! [String: Any])["name"] as? String == "Hannes")
        #expect(RealtimeProtocol.heartbeat(ref: 7).contains("\"topic\":\"phoenix\""))
    }

    @Test func decodesServerMessages() {
        // shapes captured from a live Supabase Realtime server
        #expect(RealtimeProtocol.decode(#"{"event":"phx_reply","payload":{"response":{"postgres_changes":[]},"status":"ok"},"ref":"1","topic":"realtime:t"}"#) == .joined)
        #expect(RealtimeProtocol.decode(#"{"event":"phx_reply","payload":{"response":{},"status":"ok"},"ref":"9","topic":"realtime:t"}"#) == .other)
        if case .joinFailed = RealtimeProtocol.decode(#"{"event":"phx_reply","payload":{"response":{"reason":"nope"},"status":"error"},"ref":"1","topic":"t"}"#) {} else { Issue.record("join failure") }
        let msg = RealtimeProtocol.broadcast(topic: "realtime:t", state: state, ref: 3)
        #expect(RealtimeProtocol.decode(msg) == .state(state))
        #expect(RealtimeProtocol.decode(#"{"event":"presence_diff","payload":{"joins":{},"leaves":{"abc":{"metas":[]}}},"ref":null,"topic":"t"}"#) == .left(id: "abc"))
        #expect(RealtimeProtocol.decode("not json") == .other)
    }

    @Test func untrustedStateIsSanitized() {
        var bad = state
        bad.name = String(repeating: "x", count: 100)
        bad.speed = 9999
        bad.jersey = 99
        let s = bad.sanitized()!
        #expect(s.name.count == 24 && s.speed == 30 && s.jersey == RiderProfile.jerseyPalette.count - 1)
        bad.distance = .nan
        #expect(bad.sanitized() == nil)
    }

    @Test func storeExtrapolatesAndExpires() {
        var store = RemoteRiderStore()
        store.update(state, now: 100)
        let r = store.riders(routeId: "skogsslingan", now: 101)
        #expect(r.count == 1 && abs(r[0].distance - (1234.5 + 9.5)) < 1e-9)
        #expect(store.riders(routeId: "other", now: 101).isEmpty)
        #expect(abs(store.riders(routeId: "skogsslingan", now: 107)[0].distance - (1234.5 + 9.5 * 3)) < 1e-9, "capped extrapolation")
        store.prune(now: 120)
        #expect(store.count == 0)
    }

    @Test func engineMapsRemoteRidersToNearestLapAndDrafts() {
        let route = RouteBuilder.build(RouteLibrary.skogsslingan)
        let e = RideEngine(config: .init(route: route, rider: RiderProfile(name: "Jag")))
        for _ in 0..<200 { e.tick(dt: 0.1, inputs: RideInputs(power: 200)) }
        var friend = state
        // a full lap ahead plus 2 m → should appear 2 m in front of me
        friend.distance = e.distance + route.length + 2
        e.setRemoteRiders([friend])
        #expect(abs(e.remoteRiders[0].effectiveDistance - (e.distance + 2)) < 1e-6)
        e.tick(dt: 0.1, inputs: RideInputs(power: 200))
        #expect(e.draftFactor < 0.8, "drafting behind a real rider")
        let board = e.leaderboard()
        #expect(board.contains { $0.isRemote && $0.name == "Hannes" })
        let mine = e.broadcastState(id: "me")
        #expect(mine.routeId == "skogsslingan" && mine.name == "Jag")
    }
}
