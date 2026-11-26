import Foundation

/// One second of recorded ride data.
public struct RideSample: Codable, Equatable, Sendable {
    /// Seconds since start (timer time, pauses excluded).
    public var t: Int
    public var power: Int
    public var heartRate: Int?
    public var cadence: Int?
    /// m/s
    public var speed: Double
    /// metres, cumulative
    public var distance: Double
    public var elevation: Double
    public var grade: Double

    public init(t: Int, power: Int, heartRate: Int?, cadence: Int?, speed: Double, distance: Double, elevation: Double, grade: Double) {
        self.t = t
        self.power = power
        self.heartRate = heartRate
        self.cadence = cadence
        self.speed = speed
        self.distance = distance
        self.elevation = elevation
        self.grade = grade
    }
}

public struct SegmentResult: Codable, Equatable, Sendable {
    public var segmentId: String
    public var name: String
    public var kind: RouteSegment.Kind
    public var seconds: Double
    public var averagePower: Double
    public var isPersonalBest: Bool
}

public struct BestEffort: Codable, Equatable, Sendable {
    public var seconds: Int
    public var watts: Double
}

/// Aggregates computed from a list of 1 Hz samples.
public struct RideStats: Codable, Equatable, Sendable {
    public var duration: Int = 0
    public var distance: Double = 0
    public var ascent: Double = 0
    public var averagePower: Double = 0
    public var maxPower: Int = 0
    public var normalizedPower: Double = 0
    public var intensityFactor: Double = 0
    public var tss: Double = 0
    public var kilojoules: Double = 0
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    public var averageCadence: Int?
    public var averageSpeed: Double = 0
    public var maxSpeed: Double = 0
    public var bestEfforts: [BestEffort] = []
    /// Seconds in each power zone (index 0 = Z1).
    public var timeInZones: [Int] = Array(repeating: 0, count: 7)

    public init() {}

    public static let effortDurations = [5, 60, 300, 1200]

    public static func compute(samples: [RideSample], ftp: Double) -> RideStats {
        var s = RideStats()
        guard !samples.isEmpty else { return s }
        let powers = samples.map { Double($0.power) }
        s.duration = samples.count
        s.distance = samples.last!.distance - samples.first!.distance
        var ascent = 0.0
        for i in 1..<samples.count {
            let d = samples[i].elevation - samples[i - 1].elevation
            if d > 0 { ascent += d }
        }
        s.ascent = ascent
        s.averagePower = powers.reduce(0, +) / Double(powers.count)
        s.maxPower = samples.map(\.power).max() ?? 0
        s.kilojoules = powers.reduce(0, +) / 1000
        s.normalizedPower = normalizedPower(powers)
        if ftp > 0 {
            s.intensityFactor = s.normalizedPower / ftp
            s.tss = Double(s.duration) * s.normalizedPower * s.intensityFactor / (ftp * 3600) * 100
        }
        let hrs = samples.compactMap(\.heartRate)
        if !hrs.isEmpty {
            s.averageHeartRate = Int((Double(hrs.reduce(0, +)) / Double(hrs.count)).rounded())
            s.maxHeartRate = hrs.max()
        }
        // average cadence while pedalling
        let cads = samples.compactMap(\.cadence).filter { $0 > 0 }
        if !cads.isEmpty { s.averageCadence = Int((Double(cads.reduce(0, +)) / Double(cads.count)).rounded()) }
        s.averageSpeed = s.distance / Double(s.duration)
        s.maxSpeed = samples.map(\.speed).max() ?? 0
        s.bestEfforts = effortDurations.compactMap { d in
            bestAverage(powers, window: d).map { BestEffort(seconds: d, watts: $0) }
        }
        for p in powers {
            s.timeInZones[PowerZone.zone(power: p, ftp: ftp).rawValue - 1] += 1
        }
        return s
    }

    /// Coggan normalized power: 4th-root of the mean of 30 s rolling average⁴.
    public static func normalizedPower(_ p: [Double]) -> Double {
        guard p.count >= 30 else {
            return p.isEmpty ? 0 : p.reduce(0, +) / Double(p.count)
        }
        var sum = p[0..<30].reduce(0, +)
        var acc = pow(sum / 30, 4)
        var n = 1.0
        for i in 30..<p.count {
            sum += p[i] - p[i - 30]
            acc += pow(sum / 30, 4)
            n += 1
        }
        return pow(acc / n, 0.25)
    }

    /// Highest mean power over any `window` consecutive seconds.
    public static func bestAverage(_ p: [Double], window: Int) -> Double? {
        guard window > 0, p.count >= window else { return nil }
        var sum = p[0..<window].reduce(0, +)
        var best = sum
        for i in window..<p.count {
            sum += p[i] - p[i - window]
            best = max(best, sum)
        }
        return best / Double(window)
    }

    /// FTP estimate for a completed test workout.
    public static func ftpEstimate(test: Workout.TestKind, samples: [RideSample]) -> Double? {
        let p = samples.map { Double($0.power) }
        switch test {
        case .ramp: return bestAverage(p, window: 60).map { ($0 * 0.75).rounded() }
        case .twentyMinute: return bestAverage(p, window: 1200).map { ($0 * 0.95).rounded() }
        }
    }
}

/// A finished, saved ride.
public struct RideRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startDate: Date
    public var routeId: String
    public var routeName: String
    public var workoutName: String?
    public var riderWeightKg: Double
    public var ftp: Double
    public var elapsedSeconds: Int
    public var stats: RideStats
    public var segments: [SegmentResult]
    public var ftpEstimate: Double?
    public var samples: [RideSample]

    public init(
        id: UUID = UUID(), startDate: Date, routeId: String, routeName: String, workoutName: String?,
        riderWeightKg: Double, ftp: Double, elapsedSeconds: Int, stats: RideStats, segments: [SegmentResult],
        ftpEstimate: Double?, samples: [RideSample]
    ) {
        self.id = id
        self.startDate = startDate
        self.routeId = routeId
        self.routeName = routeName
        self.workoutName = workoutName
        self.riderWeightKg = riderWeightKg
        self.ftp = ftp
        self.elapsedSeconds = elapsedSeconds
        self.stats = stats
        self.segments = segments
        self.ftpEstimate = ftpEstimate
        self.samples = samples
    }
}
