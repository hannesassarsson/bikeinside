import Foundation

/// Something to earn. Checked after every saved ride.
public struct Achievement: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String

    public static let all: [Achievement] = [
        .init(id: "first-ride", title: "Första turen", detail: "Spara din första åkning.", symbol: "flag.fill"),
        .init(id: "km-100", title: "Hundra kilometer", detail: "Cykla 100 km totalt.", symbol: "road.lanes"),
        .init(id: "km-500", title: "Femhundra", detail: "Cykla 500 km totalt.", symbol: "road.lanes"),
        .init(id: "km-1000", title: "Tusen kilometer", detail: "Cykla 1 000 km totalt.", symbol: "star.fill"),
        .init(id: "climb-1000", title: "Höjdmetersamlare", detail: "Klättra 1 000 höjdmeter totalt.", symbol: "mountain.2.fill"),
        .init(id: "everest", title: "Everest hemma", detail: "Klättra 8 848 höjdmeter totalt.", symbol: "mountain.2.circle.fill"),
        .init(id: "long-ride", title: "Långpass", detail: "En åkning på minst två timmar.", symbol: "clock.fill"),
        .init(id: "ftp-test", title: "Testad", detail: "Genomför ett FTP-test.", symbol: "gauge.with.dots.needle.67percent"),
        .init(id: "pr", title: "Personbästa", detail: "Sätt personbästa på ett segment.", symbol: "trophy.fill"),
        .init(id: "workout-10", title: "Strukturerad", detail: "Kör 10 träningspass.", symbol: "chart.bar.xaxis"),
        .init(id: "all-worlds", title: "Världsresenär", detail: "Cykla i alla världar.", symbol: "globe.europe.africa.fill"),
        .init(id: "tss-100", title: "Hårt jobbat", detail: "En åkning med minst 100 TSS.", symbol: "flame.fill"),
    ]

    public static func with(id: String) -> Achievement? { all.first { $0.id == id } }
}

/// Lifetime totals, XP, level and earned achievements.
public struct Progression: Codable, Equatable, Sendable {
    public var xp: Int = 0
    public var achievements: Set<String> = []
    public var totalDistance: Double = 0
    public var totalAscent: Double = 0
    public var totalSeconds: Int = 0
    public var rides: Int = 0
    public var workouts: Int = 0
    public var routesRidden: Set<String> = []

    public init() {}

    /// Level 1 at 0 XP; each level needs 400 XP more than the previous one.
    public static func xpRequired(forLevel level: Int) -> Int {
        let n = max(level - 1, 0)
        return 200 * n * (n + 1)
    }

    public static func level(forXP xp: Int) -> Int {
        var l = 1
        while l < 60 && xpRequired(forLevel: l + 1) <= xp { l += 1 }
        return l
    }

    public var level: Int { Self.level(forXP: xp) }

    /// 0…1 progress towards the next level.
    public var levelProgress: Double {
        let lo = Self.xpRequired(forLevel: level), hi = Self.xpRequired(forLevel: level + 1)
        return hi > lo ? Double(xp - lo) / Double(hi - lo) : 1
    }

    /// Jersey colours (indices into `RiderProfile.jerseyPalette`) and the level that unlocks them.
    public static let jerseyUnlockLevel: [Int: Int] = [
        0: 1, 1: 1, 2: 1, 3: 1, 4: 3, 5: 5, 6: 7, 7: 9, 8: 12, 9: 15, 10: 20,
    ]

    public func isJerseyUnlocked(_ index: Int) -> Bool {
        level >= (Self.jerseyUnlockLevel[index] ?? 1)
    }

    /// XP for a ride: distance, climbing and time, plus bonuses.
    public static func xp(for ride: RideRecord, workoutCompleted: Bool) -> Int {
        let km = ride.stats.distance / 1000
        var xp = Int((km * 10).rounded()) + Int((ride.stats.ascent / 10).rounded()) + ride.stats.duration / 60
        if workoutCompleted { xp += 50 }
        xp += ride.segments.filter(\.isPersonalBest).count * 15
        return max(xp, 0)
    }

    public struct Update: Equatable, Sendable {
        public var xpGained: Int
        public var levelBefore: Int
        public var levelAfter: Int
        public var newAchievements: [String]
        public var newJerseys: [Int]

        public var leveledUp: Bool { levelAfter > levelBefore }
    }

    /// Adds a saved ride and returns what changed.
    @discardableResult
    public mutating func apply(_ ride: RideRecord, workoutCompleted: Bool, allRouteIds: [String]) -> Update {
        let before = level
        let unlockedBefore = Set(RiderProfile.jerseyPalette.indices.filter { isJerseyUnlocked($0) })
        let gained = Self.xp(for: ride, workoutCompleted: workoutCompleted)
        xp += gained
        rides += 1
        totalDistance += ride.stats.distance
        totalAscent += ride.stats.ascent
        totalSeconds += ride.stats.duration
        if workoutCompleted { workouts += 1 }
        routesRidden.insert(ride.routeId)

        var earned: [String] = []
        func earn(_ id: String, _ condition: Bool) {
            if condition && !achievements.contains(id) {
                achievements.insert(id)
                earned.append(id)
            }
        }
        earn("first-ride", rides >= 1)
        earn("km-100", totalDistance >= 100_000)
        earn("km-500", totalDistance >= 500_000)
        earn("km-1000", totalDistance >= 1_000_000)
        earn("climb-1000", totalAscent >= 1000)
        earn("everest", totalAscent >= 8848)
        earn("long-ride", ride.stats.duration >= 7200)
        earn("ftp-test", ride.ftpEstimate != nil)
        earn("pr", ride.segments.contains { $0.isPersonalBest })
        earn("workout-10", workouts >= 10)
        earn("all-worlds", !allRouteIds.isEmpty && Set(allRouteIds).isSubset(of: routesRidden))
        earn("tss-100", ride.stats.tss >= 100)

        let unlockedAfter = Set(RiderProfile.jerseyPalette.indices.filter { isJerseyUnlocked($0) })
        return Update(xpGained: gained, levelBefore: before, levelAfter: level, newAchievements: earned,
                      newJerseys: unlockedAfter.subtracting(unlockedBefore).sorted())
    }

    /// Rebuilds progression from an existing ride history (first launch after updating).
    public static func rebuild(from history: [RideRecord], allRouteIds: [String]) -> Progression {
        var p = Progression()
        for r in history.sorted(by: { $0.startDate < $1.startDate }) {
            p.apply(r, workoutCompleted: r.workoutName != nil, allRouteIds: allRouteIds)
        }
        return p
    }
}
