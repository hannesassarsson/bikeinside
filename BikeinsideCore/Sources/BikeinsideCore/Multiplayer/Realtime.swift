import Foundation

/// State another rider broadcasts ~2 times per second.
public struct RemoteRiderState: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var jersey: Int
    public var heightCm: Double
    public var routeId: String
    /// Total distance ridden (metres); position on the route is distance mod length.
    public var distance: Double
    /// m/s
    public var speed: Double
    public var power: Double
    public var wattsPerKg: Double
    public var cadence: Double?

    public init(id: String, name: String, jersey: Int, heightCm: Double, routeId: String, distance: Double,
                speed: Double, power: Double, wattsPerKg: Double, cadence: Double?) {
        self.id = id
        self.name = name
        self.jersey = jersey
        self.heightCm = heightCm
        self.routeId = routeId
        self.distance = distance
        self.speed = speed
        self.power = power
        self.wattsPerKg = wattsPerKg
        self.cadence = cadence
    }

    /// Sanitises untrusted data from the network.
    public func sanitized() -> RemoteRiderState? {
        guard !id.isEmpty, id.count <= 64, distance.isFinite, speed.isFinite, power.isFinite, wattsPerKg.isFinite else { return nil }
        var s = self
        s.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        if s.name.isEmpty { s.name = "Cyklist" }
        s.jersey = min(max(jersey, 0), RiderProfile.jerseyPalette.count - 1)
        s.heightCm = Interp.clamp(heightCm.isFinite ? heightCm : 180, 140, 210)
        s.distance = max(0, distance)
        s.speed = Interp.clamp(speed, 0, 30)
        s.power = Interp.clamp(power, 0, 2500)
        s.wattsPerKg = Interp.clamp(wattsPerKg, 0, 30)
        if let c = cadence { s.cadence = c.isFinite ? Interp.clamp(c, 0, 200) : nil }
        return s
    }
}

/// Supabase Realtime (Phoenix channel protocol, JSON v1) message encoding and
/// decoding. Pure functions so the protocol is unit-tested without a network.
public enum RealtimeProtocol {
    public static func topic(routeId: String, room: String) -> String {
        let clean = room.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "realtime:bikeinside:\(routeId):\(clean.isEmpty ? "alla" : String(clean.prefix(32)))"
    }

    public static func websocketURL(projectURL: String, apiKey: String) -> URL? {
        guard var c = URLComponents(string: projectURL) else { return nil }
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        c.path = "/realtime/v1/websocket"
        c.queryItems = [URLQueryItem(name: "apikey", value: apiKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return c.url
    }

    static func json(_ object: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    public static func join(topic: String, presenceKey: String, ref: Int) -> String {
        json([
            "topic": topic, "event": "phx_join", "ref": String(ref),
            "payload": ["config": ["broadcast": ["self": false], "presence": ["key": presenceKey], "private": false]],
        ])
    }

    public static func leave(topic: String, ref: Int) -> String {
        json(["topic": topic, "event": "phx_leave", "ref": String(ref), "payload": [String: Any]()])
    }

    public static func heartbeat(ref: Int) -> String {
        json(["topic": "phoenix", "event": "heartbeat", "ref": String(ref), "payload": [String: Any]()])
    }

    public static func broadcast(topic: String, state: RemoteRiderState, ref: Int) -> String {
        let data = (try? JSONEncoder().encode(state)) ?? Data("{}".utf8)
        let inner = (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
        return json([
            "topic": topic, "event": "broadcast", "ref": String(ref),
            "payload": ["type": "broadcast", "event": "state", "payload": inner],
        ])
    }

    public enum Incoming: Equatable, Sendable {
        case joined
        case joinFailed(String)
        case state(RemoteRiderState)
        case left(id: String)
        case other
    }

    public static func decode(_ text: String) -> Incoming {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = obj["event"] as? String else { return .other }
        let payload = obj["payload"] as? [String: Any] ?? [:]
        switch event {
        case "phx_reply":
            // only the join reply (ref 1 by convention) matters
            guard let ref = obj["ref"] as? String, ref == "1" else { return .other }
            if (payload["status"] as? String) == "ok" { return .joined }
            return .joinFailed(String(describing: payload["response"] ?? "okänt fel"))
        case "broadcast":
            guard (payload["event"] as? String) == "state", let inner = payload["payload"],
                  let innerData = try? JSONSerialization.data(withJSONObject: inner),
                  let state = try? JSONDecoder().decode(RemoteRiderState.self, from: innerData),
                  let clean = state.sanitized() else { return .other }
            return .state(clean)
        case "presence_diff":
            if let leaves = payload["leaves"] as? [String: Any], let id = leaves.keys.first { return .left(id: id) }
            return .other
        default:
            return .other
        }
    }
}

/// Latest known state per remote rider, with dead-reckoning between updates.
public struct RemoteRiderStore: Sendable {
    struct Entry: Sendable {
        var state: RemoteRiderState
        var receivedAt: Double
    }

    private var entries: [String: Entry] = [:]
    /// Riders silent for longer than this are dropped.
    public var timeout: Double = 8

    public init() {}

    public mutating func update(_ s: RemoteRiderState, now: Double) {
        entries[s.id] = Entry(state: s, receivedAt: now)
    }

    public mutating func remove(id: String) { entries[id] = nil }

    public mutating func prune(now: Double) {
        entries = entries.filter { now - $0.value.receivedAt <= timeout }
    }

    /// Riders on `routeId`, extrapolated to `now` (capped at 3 s so a stalled
    /// connection doesn't send someone flying off).
    public func riders(routeId: String, now: Double) -> [RemoteRiderState] {
        entries.values
            .filter { $0.state.routeId == routeId && now - $0.receivedAt <= timeout }
            .map { e in
                var s = e.state
                s.distance += s.speed * min(now - e.receivedAt, 3)
                return s
            }
            .sorted { $0.id < $1.id }
    }

    public var count: Int { entries.count }
}
