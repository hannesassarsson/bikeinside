import Foundation

/// Multi-week programme built from the workout library.
public struct TrainingPlan: Identifiable, Sendable, Equatable {
    public struct Session: Sendable, Equatable {
        /// 0 = Monday … 6 = Sunday
        public var weekday: Int
        public var workoutId: String
    }

    public let id: String
    public let name: String
    public let summary: String
    /// weeks[w] lists that week's sessions.
    public let weeks: [[Session]]

    public static let all: [TrainingPlan] = [getStarted, buildBase, raiseFTP]

    public static func plan(id: String) -> TrainingPlan? { all.first { $0.id == id } }

    static func s(_ d: Int, _ w: String) -> Session { Session(weekday: d, workoutId: w) }

    public static let getStarted = TrainingPlan(
        id: "kom-igang", name: "Kom igång (3 veckor)",
        summary: "Tre pass i veckan. Lär känna trainern, hitta din FTP och bygg vanan.",
        weeks: [
            [s(0, "recovery-30"), s(2, "endurance-60"), s(5, "ftp-ramp")],
            [s(0, "endurance-60"), s(2, "tempo-3x12"), s(5, "endurance-60")],
            [s(0, "recovery-30"), s(2, "sweetspot-3x10"), s(5, "endurance-60")],
        ])

    public static let buildBase = TrainingPlan(
        id: "bygg-bas", name: "Bygg bas (4 veckor)",
        summary: "Mycket zon 2 och tempo med en lugn fjärde vecka. Grunden för allt annat.",
        weeks: [
            [s(0, "endurance-60"), s(1, "tempo-3x12"), s(3, "endurance-60"), s(5, "endurance-60")],
            [s(0, "endurance-60"), s(1, "sweetspot-3x10"), s(3, "endurance-60"), s(5, "tempo-3x12")],
            [s(0, "endurance-60"), s(1, "sweetspot-3x10"), s(3, "tempo-3x12"), s(5, "endurance-60")],
            [s(0, "recovery-30"), s(2, "endurance-60"), s(5, "recovery-30")],
        ])

    public static let raiseFTP = TrainingPlan(
        id: "hoj-ftp", name: "Höj FTP (6 veckor)",
        summary: "Sweet spot, tröskel och VO2max i block, med test i början och slutet.",
        weeks: [
            [s(0, "ftp-ramp"), s(2, "endurance-60"), s(4, "sweetspot-3x10"), s(6, "endurance-60")],
            [s(0, "sweetspot-3x10"), s(2, "endurance-60"), s(4, "over-under"), s(6, "endurance-60")],
            [s(0, "threshold-2x20"), s(2, "recovery-30"), s(4, "vo2-5x3"), s(6, "endurance-60")],
            [s(0, "recovery-30"), s(2, "endurance-60"), s(5, "bursts-30-30")],
            [s(0, "threshold-2x20"), s(2, "endurance-60"), s(4, "pyramid"), s(6, "vo2-5x3")],
            [s(0, "sweetspot-3x10"), s(2, "recovery-30"), s(5, "ftp-ramp")],
        ])

    public struct Scheduled: Sendable, Equatable {
        public var date: Date
        public var week: Int
        public var workoutId: String
        public var done: Bool
    }

    /// Concrete dates for every session, starting on the Monday of `start`'s week.
    /// A session counts as done if a ride with that workout happened on or after
    /// its date within the same plan week.
    public func schedule(start: Date, completed: [(date: Date, workoutId: String)], calendar: Calendar = .swedish) -> [Scheduled] {
        let monday = calendar.startOfWeek(for: start)
        var used = Set<Int>()
        var out: [Scheduled] = []
        for (w, sessions) in weeks.enumerated() {
            for s in sessions {
                let date = calendar.date(byAdding: .day, value: w * 7 + s.weekday, to: monday)!
                let weekEnd = calendar.date(byAdding: .day, value: (w + 1) * 7, to: monday)!
                let match = completed.indices.first { i in
                    !used.contains(i) && completed[i].workoutId == s.workoutId
                        && completed[i].date >= calendar.startOfDay(for: date) && completed[i].date < weekEnd
                }
                if let m = match { used.insert(m) }
                out.append(Scheduled(date: date, week: w, workoutId: s.workoutId, done: match != nil))
            }
        }
        return out
    }
}

extension Calendar {
    /// Monday-first Gregorian calendar in Swedish time.
    public static var swedish: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "sv_SE")
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }

    public func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }
}

/// Fitness (CTL), fatigue (ATL) and form (TSB) from daily training stress.
public enum TrainingLoad {
    public struct Day: Sendable, Equatable {
        public var date: Date
        public var tss: Double
        public var fitness: Double
        public var fatigue: Double
        public var form: Double { fitness - fatigue }
    }

    /// Exponentially weighted 42-day (fitness) and 7-day (fatigue) loads, one
    /// value per day from the first ride through `until`.
    public static func series(rides: [(date: Date, tss: Double)], until: Date, calendar: Calendar = .swedish) -> [Day] {
        guard let first = rides.map(\.date).min() else { return [] }
        var daily: [Date: Double] = [:]
        for r in rides { daily[calendar.startOfDay(for: r.date), default: 0] += r.tss }
        var day = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: until)
        var ctl = 0.0, atl = 0.0
        var out: [Day] = []
        let kc = 1 - exp(-1.0 / 42), ka = 1 - exp(-1.0 / 7)
        while day <= end {
            let tss = daily[day] ?? 0
            ctl += (tss - ctl) * kc
            atl += (tss - atl) * ka
            out.append(Day(date: day, tss: tss, fitness: ctl, fatigue: atl))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }

    /// Best power for each effort duration across many rides.
    public static func powerCurve(_ rides: [RideStats]) -> [BestEffort] {
        RideStats.effortDurations.compactMap { d in
            rides.compactMap { $0.bestEfforts.first { $0.seconds == d }?.watts }.max().map { BestEffort(seconds: d, watts: $0) }
        }
    }
}
