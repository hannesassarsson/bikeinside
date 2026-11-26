import Foundation

/// Power target for a workout step: relative to FTP or absolute.
public enum PowerTarget: Codable, Equatable, Sendable {
    /// Fraction of FTP (0.9 = 90 %).
    case ftp(Double)
    case watts(Double)

    public func watts(ftp: Double) -> Double {
        switch self {
        case .ftp(let f): return f * ftp
        case .watts(let w): return w
        }
    }

    public func fraction(ftp: Double) -> Double {
        switch self {
        case .ftp(let f): return f
        case .watts(let w): return ftp > 0 ? w / ftp : 0
        }
    }
}

public struct WorkoutStep: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case warmup, work, recovery, cooldown, steady, ramp, free
    }

    public var kind: Kind
    public var duration: Double
    public var start: PowerTarget
    public var end: PowerTarget
    public var cadence: Int?
    public var label: String

    public init(kind: Kind, duration: Double, start: PowerTarget, end: PowerTarget? = nil, cadence: Int? = nil, label: String) {
        self.kind = kind
        self.duration = duration
        self.start = start
        self.end = end ?? start
        self.cadence = cadence
        self.label = label
    }

    /// Free steps have no ERG target: the rider decides (e.g. an all-out test effort).
    public var isFree: Bool { kind == .free }

    public func watts(at t: Double, ftp: Double) -> Double {
        let u = duration > 0 ? Interp.clamp(t / duration, 0, 1) : 0
        return Interp.mix(start.watts(ftp: ftp), end.watts(ftp: ftp), u)
    }
}

public struct Workout: Codable, Equatable, Sendable, Identifiable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case recovery, endurance, tempo, threshold, vo2max, sprint, test, custom

        public var displayName: String {
            switch self {
            case .recovery: return "Återhämtning"
            case .endurance: return "Uthållighet"
            case .tempo: return "Tempo & Sweet spot"
            case .threshold: return "Tröskel"
            case .vo2max: return "VO2max"
            case .sprint: return "Sprint"
            case .test: return "Tester"
            case .custom: return "Importerade"
            }
        }
    }

    public enum TestKind: String, Codable, Sendable {
        /// FTP = 75 % of best 1-minute power.
        case ramp
        /// FTP = 95 % of best 20-minute power.
        case twentyMinute
    }

    public var id: String
    public var name: String
    public var summary: String
    public var category: Category
    public var steps: [WorkoutStep]
    public var test: TestKind?

    public init(id: String, name: String, summary: String, category: Category, steps: [WorkoutStep], test: TestKind? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.steps = steps
        self.test = test
    }

    public var duration: Double { steps.reduce(0) { $0 + $1.duration } }

    public struct Position: Equatable, Sendable {
        public var index: Int
        public var elapsedInStep: Double
        public var remainingInStep: Double
    }

    /// Where in the workout we are at time `t`; nil once it has finished.
    public func position(at t: Double) -> Position? {
        guard t >= 0 else { return Position(index: 0, elapsedInStep: 0, remainingInStep: steps.first?.duration ?? 0) }
        var acc = 0.0
        for (i, s) in steps.enumerated() {
            if t < acc + s.duration {
                return Position(index: i, elapsedInStep: t - acc, remainingInStep: acc + s.duration - t)
            }
            acc += s.duration
        }
        return nil
    }

    public func startTime(ofStep index: Int) -> Double {
        steps.prefix(index).reduce(0) { $0 + $1.duration }
    }

    /// Target power at time `t`, nil for free steps or after the end.
    public func targetWatts(at t: Double, ftp: Double) -> Double? {
        guard let p = position(at: t) else { return nil }
        let s = steps[p.index]
        return s.isFree ? nil : s.watts(at: p.elapsedInStep, ftp: ftp)
    }

    /// Estimated Training Stress Score at 100 % compliance.
    public func estimatedTSS(ftp: Double) -> Double {
        var sum = 0.0
        for s in steps {
            // integrate IF² over the step (exact for linear ramps)
            let a = s.start.fraction(ftp: ftp), b = s.end.fraction(ftp: ftp)
            let meanSquare = s.isFree ? 1.0 : (a * a + a * b + b * b) / 3
            sum += meanSquare * s.duration
        }
        return sum / 3600 * 100
    }

    /// Largest target as a fraction of FTP (for chart scaling).
    public func peakFraction(ftp: Double) -> Double {
        steps.map { max($0.start.fraction(ftp: ftp), $0.end.fraction(ftp: ftp)) }.max() ?? 1
    }
}

/// Small DSL so the built-in library reads like a training plan.
public struct WorkoutBuilder {
    public private(set) var steps: [WorkoutStep] = []

    public init() {}

    public mutating func warmup(minutes: Double, from a: Double = 0.45, to b: Double = 0.70) {
        steps.append(WorkoutStep(kind: .warmup, duration: minutes * 60, start: .ftp(a), end: .ftp(b), label: "Uppvärmning"))
    }

    public mutating func cooldown(minutes: Double, from a: Double = 0.65, to b: Double = 0.40) {
        steps.append(WorkoutStep(kind: .cooldown, duration: minutes * 60, start: .ftp(a), end: .ftp(b), label: "Nedvarvning"))
    }

    public mutating func steady(seconds: Double, at f: Double, label: String = "Jämnt", cadence: Int? = nil) {
        steps.append(WorkoutStep(kind: f >= 0.76 ? .work : .steady, duration: seconds, start: .ftp(f), cadence: cadence, label: label))
    }

    public mutating func steady(minutes: Double, at f: Double, label: String = "Jämnt", cadence: Int? = nil) {
        steady(seconds: minutes * 60, at: f, label: label, cadence: cadence)
    }

    public mutating func recover(seconds: Double, at f: Double = 0.5) {
        steps.append(WorkoutStep(kind: .recovery, duration: seconds, start: .ftp(f), label: "Vila"))
    }

    public mutating func intervals(
        _ reps: Int, on onSeconds: Double, at onF: Double, off offSeconds: Double, at offF: Double = 0.5,
        cadence: Int? = nil, label: String = "Intervall", recoverAfterLast: Bool = true
    ) {
        for k in 1...reps {
            steps.append(WorkoutStep(kind: .work, duration: onSeconds, start: .ftp(onF), cadence: cadence, label: "\(label) \(k)/\(reps)"))
            if k < reps || recoverAfterLast {
                steps.append(WorkoutStep(kind: .recovery, duration: offSeconds, start: .ftp(offF), label: "Vila"))
            }
        }
    }

    public mutating func free(minutes: Double, label: String) {
        steps.append(WorkoutStep(kind: .free, duration: minutes * 60, start: .ftp(1.0), label: label))
    }

    public mutating func append(_ step: WorkoutStep) { steps.append(step) }
}
