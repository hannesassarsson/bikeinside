import Foundation

/// One night/day of recovery data (from Garmin via garmin-bridge, or entered by hand).
public struct HealthDay: Codable, Equatable, Sendable {
    public var day: String
    public var sleepHours: Double?
    public var sleepScore: Double?
    public var hrvLastNight: Double?
    public var hrvWeeklyAvg: Double?
    public var hrvBaselineLow: Double?
    public var hrvBaselineHigh: Double?
    public var hrvStatus: String?
    public var restingHR: Double?
    public var restingHR7dAvg: Double?
    public var bodyBatteryHigh: Double?
    public var trainingReadiness: Double?
    public var trainingReadinessLevel: String?

    enum CodingKeys: String, CodingKey {
        case day
        case sleepHours = "sleep_hours"
        case sleepScore = "sleep_score"
        case hrvLastNight = "hrv_last_night"
        case hrvWeeklyAvg = "hrv_weekly_avg"
        case hrvBaselineLow = "hrv_baseline_low"
        case hrvBaselineHigh = "hrv_baseline_high"
        case hrvStatus = "hrv_status"
        case restingHR = "resting_hr"
        case restingHR7dAvg = "resting_hr_7d_avg"
        case bodyBatteryHigh = "body_battery_high"
        case trainingReadiness = "training_readiness"
        case trainingReadinessLevel = "training_readiness_level"
    }

    public init(day: String, sleepHours: Double? = nil, sleepScore: Double? = nil, hrvLastNight: Double? = nil,
                hrvWeeklyAvg: Double? = nil, hrvBaselineLow: Double? = nil, hrvBaselineHigh: Double? = nil,
                hrvStatus: String? = nil, restingHR: Double? = nil, restingHR7dAvg: Double? = nil,
                bodyBatteryHigh: Double? = nil, trainingReadiness: Double? = nil, trainingReadinessLevel: String? = nil) {
        self.day = day
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
        self.hrvLastNight = hrvLastNight
        self.hrvWeeklyAvg = hrvWeeklyAvg
        self.hrvBaselineLow = hrvBaselineLow
        self.hrvBaselineHigh = hrvBaselineHigh
        self.hrvStatus = hrvStatus
        self.restingHR = restingHR
        self.restingHR7dAvg = restingHR7dAvg
        self.bodyBatteryHigh = bodyBatteryHigh
        self.trainingReadiness = trainingReadiness
        self.trainingReadinessLevel = trainingReadinessLevel
    }
}

/// How you feel this morning, 1 (dåligt) … 5 (toppen).
public struct CheckIn: Codable, Equatable, Sendable {
    public var legs: Int
    public var energy: Int
    public var date: Date

    public init(legs: Int, energy: Int, date: Date = Date()) {
        self.legs = min(max(legs, 1), 5)
        self.energy = min(max(energy, 1), 5)
        self.date = date
    }
}

/// Today's readiness to train and what to do about the planned workout.
public struct Readiness: Equatable, Sendable {
    public enum Advice: Equatable, Sendable {
        /// Ride as planned.
        case asPlanned
        /// Same workout at reduced intensity (multiplier, e.g. 0.92).
        case reduce(Double)
        /// Swap to an easy endurance ride.
        case easier
        /// Recovery spin or day off.
        case rest
    }

    /// 0…100
    public var score: Int
    public var advice: Advice
    /// Human-readable reasons in Swedish.
    public var reasons: [String]
    public var source: String

    public var title: String {
        switch advice {
        case .asPlanned: return "Redo att köra"
        case .reduce: return "Lite sliten – sänk intensiteten"
        case .easier: return "Ta det lugnt idag"
        case .rest: return "Kroppen behöver vila"
        }
    }

    /// Combines Garmin data (if any) with today's check-in (if any).
    public static func assess(days: [HealthDay], checkIn: CheckIn?, today: String) -> Readiness? {
        let latest = days.first { $0.day == today } ?? days.first
        guard latest != nil || checkIn != nil else { return nil }
        var score = 70.0
        var weightSum = 0.0
        var parts: [(Double, Double)] = [] // (score, weight)
        var reasons: [String] = []
        var source: [String] = []

        if let d = latest {
            source.append("Garmin \(d.day)")
            if let tr = d.trainingReadiness {
                parts.append((tr, 3))
                reasons.append("Training Readiness \(Int(tr))")
            }
            if let hrv = d.hrvLastNight, let lo = d.hrvBaselineLow, let hi = d.hrvBaselineHigh, hi > lo {
                let s: Double
                if hrv < lo {
                    s = Interp.clamp(50 - (lo - hrv) / lo * 200, 10, 50)
                    reasons.append("HRV \(Int(hrv)) under ditt normalspann (\(Int(lo))–\(Int(hi)))")
                } else if hrv > hi * 1.15 {
                    s = 65
                    reasons.append("HRV \(Int(hrv)) ovanligt högt")
                } else {
                    s = 75
                    reasons.append("HRV \(Int(hrv)) inom normalspannet")
                }
                parts.append((s, 2))
            }
            if let rhr = d.restingHR, let avg = d.restingHR7dAvg, avg > 0 {
                let diff = rhr - avg
                let s = Interp.clamp(75 - diff * 8, 20, 90)
                parts.append((s, 1.5))
                if diff >= 4 { reasons.append("Vilopuls \(Int(rhr)), \(Int(diff)) slag över snittet") }
            }
            if let h = d.sleepHours {
                let s = Interp.clamp((h - 4) / 4 * 90, 10, 95)
                parts.append((s, 1.5))
                if h < 6.5 { reasons.append("Bara \(Format.hours(h)) sömn") } else { reasons.append("\(Format.hours(h)) sömn") }
            }
            if let bb = d.bodyBatteryHigh {
                parts.append((Interp.clamp(bb, 0, 100), 1))
                if bb < 50 { reasons.append("Body Battery max \(Int(bb))") }
            }
        }
        if let c = checkIn {
            source.append("din incheckning")
            let s = Double(c.legs + c.energy - 2) / 8 * 100
            parts.append((s, 2))
            if c.legs <= 2 { reasons.append("Tunga ben") }
            if c.energy <= 2 { reasons.append("Låg energi") }
        }
        if !parts.isEmpty {
            weightSum = parts.reduce(0) { $0 + $1.1 }
            score = parts.reduce(0) { $0 + $1.0 * $1.1 } / weightSum
        }
        let s = Int(score.rounded())
        let advice: Advice
        switch s {
        case 72...: advice = .asPlanned
        case 55..<72: advice = .reduce(0.92)
        case 35..<55: advice = .easier
        default: advice = .rest
        }
        return Readiness(score: s, advice: advice, reasons: reasons, source: source.joined(separator: " + "))
    }

    /// What to ride instead, given the planned workout (nil = keep it).
    public func alternative(for planned: Workout?, ftp: Double) -> Workout? {
        switch advice {
        case .asPlanned, .reduce:
            return nil
        case .easier:
            guard let p = planned, p.estimatedTSS(ftp: ftp) / (p.duration / 3600) > 55 else { return nil }
            return WorkoutLibrary.enduranceHour
        case .rest:
            return planned?.id == WorkoutLibrary.recoverySpin.id ? nil : WorkoutLibrary.recoverySpin
        }
    }

    /// Intensity multiplier to start the workout with.
    public var intensity: Double {
        if case .reduce(let m) = advice { return m }
        return 1
    }
}

enum Format {
    static func hours(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        return "\(total / 60) h \(total % 60) min"
    }
}
