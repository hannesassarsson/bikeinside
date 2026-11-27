import Foundation

/// Time-vs-distance trace of one full lap. The fastest lap on a route is kept
/// and replayed as a "ghost" you can race.
public struct GhostTrack: Codable, Equatable, Sendable {
    public var routeId: String
    public var lapSeconds: Double
    /// Distance between trace points (metres).
    public var step: Double
    /// times[k] = seconds into the lap when the rider passed k * step metres.
    public var times: [Double]
    public var recordedAt: Date

    public init(routeId: String, lapSeconds: Double, step: Double, times: [Double], recordedAt: Date = Date()) {
        self.routeId = routeId
        self.lapSeconds = lapSeconds
        self.step = step
        self.times = times
        self.recordedAt = recordedAt
    }

    /// Seconds into the lap at which the ghost reached `distance` (metres into the lap).
    public func time(atDistance d: Double) -> Double {
        guard times.count > 1 else { return 0 }
        let f = max(d, 0) / step
        let i = Int(f)
        if i >= times.count - 1 { return lapSeconds }
        let t = f - Double(i)
        return times[i] + (times[i + 1] - times[i]) * t
    }

    /// Metres into the lap the ghost has covered after `t` seconds.
    public func distance(atTime t: Double) -> Double {
        guard times.count > 1, t > 0 else { return 0 }
        if t >= times.last! { return Double(times.count - 1) * step }
        // binary search for the bracketing pair
        var lo = 0, hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= t { lo = mid } else { hi = mid }
        }
        let span = times[hi] - times[lo]
        let frac = span > 0 ? (t - times[lo]) / span : 0
        return (Double(lo) + frac) * step
    }
}

/// Records the current lap's trace; produces a GhostTrack when the lap completes.
struct LapTraceRecorder: Sendable {
    let step: Double
    private(set) var times: [Double] = [0]
    private var lastTime = 0.0
    private var lastDistance = 0.0

    init(step: Double = 10) { self.step = step }

    /// Feed the lap time and distance into the lap after every tick.
    mutating func add(lapTime: Double, lapDistance: Double) {
        while Double(times.count) * step <= lapDistance {
            let mark = Double(times.count) * step
            let span = lapDistance - lastDistance
            let frac = span > 0 ? (mark - lastDistance) / span : 1
            times.append(lastTime + (lapTime - lastTime) * frac)
        }
        lastTime = lapTime
        lastDistance = lapDistance
    }

    mutating func reset() {
        times = [0]
        lastTime = 0
        lastDistance = 0
    }
}
