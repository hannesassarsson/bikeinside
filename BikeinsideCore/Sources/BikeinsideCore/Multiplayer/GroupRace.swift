import Foundation

/// A quick message to everyone in the room ("Heja!", emojis).
public struct Cheer: Codable, Equatable, Sendable {
    public var from: String
    public var name: String
    public var text: String

    public init(from: String, name: String, text: String) {
        self.from = from
        self.name = name
        self.text = text
    }

    public static let presets = ["👏 Heja!", "🔥 Bra jobbat!", "💪 Kom igen!", "👋 Hej!"]

    public func sanitized() -> Cheer? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !t.isEmpty else { return nil }
        return Cheer(from: String(from.prefix(64)), name: String(name.prefix(24)), text: String(t.prefix(40)))
    }
}

/// Someone in the room starts a race: everyone rides `distance` metres from
/// wherever they are when the countdown ends.
public struct RaceAnnouncement: Codable, Equatable, Sendable {
    public var raceId: String
    public var routeId: String
    /// Unix time (seconds) when the race starts.
    public var startAt: Double
    public var distance: Double
    public var starterName: String

    public init(raceId: String, routeId: String, startAt: Double, distance: Double, starterName: String) {
        self.raceId = raceId
        self.routeId = routeId
        self.startAt = startAt
        self.distance = distance
        self.starterName = starterName
    }

    public var isValid: Bool {
        !raceId.isEmpty && distance >= 200 && distance <= 100_000 && startAt.isFinite
    }
}

public struct RaceFinish: Codable, Equatable, Sendable {
    public var raceId: String
    public var id: String
    public var name: String
    public var seconds: Double

    public init(raceId: String, id: String, name: String, seconds: Double) {
        self.raceId = raceId
        self.id = id
        self.name = name
        self.seconds = seconds
    }
}

/// Client-side race state machine.
public struct RaceTracker: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case countdown(secondsLeft: Int)
        case racing(progress: Double, elapsed: Double)
        case finished(seconds: Double, place: Int)
    }

    public private(set) var race: RaceAnnouncement?
    public private(set) var results: [RaceFinish] = []
    private var startDistance: Double?
    private var myFinish: Double?
    private var myId: String = ""

    public init() {}

    /// Accepts a new announcement (ignores duplicates and races on other routes).
    public mutating func announce(_ a: RaceAnnouncement, routeId: String, myId: String) -> Bool {
        guard a.isValid, a.routeId == routeId, race?.raceId != a.raceId else { return false }
        if case .racing = phase(now: Date().timeIntervalSince1970, distance: 0) { return false }
        race = a
        results = []
        startDistance = nil
        myFinish = nil
        self.myId = myId
        return true
    }

    public mutating func record(_ f: RaceFinish) {
        guard f.raceId == race?.raceId, f.seconds.isFinite, f.seconds > 0, !results.contains(where: { $0.id == f.id }) else { return }
        results.append(f)
        results.sort { $0.seconds < $1.seconds }
    }

    /// Advance with the local clock (unix seconds) and the rider's total distance.
    /// Returns a finish to broadcast the moment the rider crosses the line.
    public mutating func update(now: Double, distance: Double, myName: String) -> RaceFinish? {
        guard let r = race, now >= r.startAt else { return nil }
        if startDistance == nil { startDistance = distance }
        guard myFinish == nil, let s = startDistance, distance - s >= r.distance else { return nil }
        let secs = now - r.startAt
        myFinish = secs
        let f = RaceFinish(raceId: r.raceId, id: myId, name: myName, seconds: secs)
        record(f)
        return f
    }

    public func phase(now: Double, distance: Double) -> Phase {
        guard let r = race else { return .idle }
        if now < r.startAt { return .countdown(secondsLeft: Int((r.startAt - now).rounded(.up))) }
        if let f = myFinish {
            let place = (results.firstIndex { $0.id == myId } ?? results.count) + 1
            return .finished(seconds: f, place: place)
        }
        let progress = startDistance.map { Interp.clamp((distance - $0) / r.distance, 0, 1) } ?? 0
        return .racing(progress: progress, elapsed: now - r.startAt)
    }

    /// Metres left to the finish line.
    public func remaining(distance: Double) -> Double? {
        guard let r = race, let s = startDistance, myFinish == nil else { return nil }
        return max(0, r.distance - (distance - s))
    }

    public mutating func clear() {
        race = nil
        results = []
        startDistance = nil
        myFinish = nil
    }
}
