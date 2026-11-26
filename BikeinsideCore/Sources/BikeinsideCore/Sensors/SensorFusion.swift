import Foundation

/// What a connected device is used for.
public enum SensorRole: String, Codable, Sendable, CaseIterable {
    case trainer, powerMeter, heartRate, cadence

    public var displayName: String {
        switch self {
        case .trainer: return "Smart trainer"
        case .powerMeter: return "Wattmätare"
        case .heartRate: return "Pulsband"
        case .cadence: return "Kadenssensor"
        }
    }
}

/// Combined live values the ride engine consumes.
public struct RideInputs: Equatable, Sendable {
    public var power: Double?
    public var cadence: Double?
    public var heartRate: Int?

    public init(power: Double? = nil, cadence: Double? = nil, heartRate: Int? = nil) {
        self.power = power
        self.cadence = cadence
        self.heartRate = heartRate
    }
}

/// Picks the best source for each metric. A dedicated power meter beats the
/// trainer's estimate, a chest strap beats a trainer's HR relay, and values
/// older than `staleAfter` seconds are ignored so a dropped sensor falls back
/// to the next one instead of freezing.
public struct SensorHub: Sendable {
    struct Stamped<T: Sendable>: Sendable {
        var value: T
        var at: Double
    }

    public var staleAfter: Double = 3.0
    private var power: [SensorRole: Stamped<Double>] = [:]
    private var cadence: [SensorRole: Stamped<Double>] = [:]
    private var heartRate: [SensorRole: Stamped<Int>] = [:]

    public init() {}

    static let powerPriority: [SensorRole] = [.powerMeter, .trainer]
    static let cadencePriority: [SensorRole] = [.powerMeter, .cadence, .trainer]
    static let heartRatePriority: [SensorRole] = [.heartRate, .trainer, .powerMeter]

    public mutating func ingest(role: SensorRole, power p: Double? = nil, cadence c: Double? = nil, heartRate h: Int? = nil, now: Double) {
        if let p, p.isFinite, p >= 0, p < 3000 { power[role] = Stamped(value: p, at: now) }
        if let c, c.isFinite, c >= 0, c < 250 { cadence[role] = Stamped(value: c, at: now) }
        if let h, h > 25, h < 250 { heartRate[role] = Stamped(value: h, at: now) }
    }

    public mutating func remove(role: SensorRole) {
        power[role] = nil
        cadence[role] = nil
        heartRate[role] = nil
    }

    public func inputs(now: Double) -> RideInputs {
        func pick<T>(_ table: [SensorRole: Stamped<T>], _ order: [SensorRole]) -> T? {
            for role in order {
                if let s = table[role], now - s.at <= staleAfter { return s.value }
            }
            return nil
        }
        return RideInputs(
            power: pick(power, Self.powerPriority),
            cadence: pick(cadence, Self.cadencePriority),
            heartRate: pick(heartRate, Self.heartRatePriority))
    }

    /// Which role currently supplies power (for the UI).
    public func powerSource(now: Double) -> SensorRole? {
        Self.powerPriority.first { role in power[role].map { now - $0.at <= staleAfter } ?? false }
    }
}

/// What we want the trainer to do right now.
public enum TrainerTarget: Equatable, Sendable {
    case none
    /// Road feel: the trainer simulates this grade (in %, already scaled by trainer difficulty).
    case simulation(gradePercent: Double, crr: Double, windResistance: Double)
    /// ERG: hold this power regardless of cadence.
    case erg(watts: Int)
}

/// FTMS control-point state machine. Guarantees: we request control first,
/// only one command is in flight at a time (the trainer answers each with an
/// indication), setpoints are coalesced so only the newest is sent, writes are
/// rate-limited, and lost/denied control is recovered automatically.
public struct TrainerControlState: Sendable {
    public enum Phase: Equatable, Sendable { case idle, requestingControl, starting, ready }

    public private(set) var phase: Phase = .idle
    public private(set) var target: TrainerTarget = .none
    public private(set) var lastSent: TrainerTarget = .none
    public private(set) var lastError: String?
    private var inFlight: (command: FTMSCommand, at: Double)?
    private var lastSentAt: Double = -.infinity
    private var retryAfter: Double = -.infinity

    public var minInterval: Double = 0.5
    public var responseTimeout: Double = 2.0
    public var refreshInterval: Double = 8.0

    public init() {}

    /// Begin a control session (after the control point characteristic is subscribed).
    public mutating func connect() {
        phase = .requestingControl
        inFlight = nil
        lastSent = .none
        lastSentAt = -.infinity
        retryAfter = -.infinity
    }

    public mutating func disconnect() {
        phase = .idle
        inFlight = nil
        lastSent = .none
    }

    public mutating func setTarget(_ t: TrainerTarget) { target = t }

    public var isAwaitingResponse: Bool { inFlight != nil }

    /// Returns the next command to write, if any. Call regularly (e.g. 10 Hz).
    public mutating func nextCommand(now: Double) -> FTMSCommand? {
        if let f = inFlight {
            guard now - f.at > responseTimeout else { return nil }
            inFlight = nil // no answer: assume lost and carry on
            if phase != .ready { phase = .requestingControl }
            retryAfter = now + 1
        }
        guard now >= retryAfter else { return nil }
        let cmd: FTMSCommand?
        switch phase {
        case .idle:
            cmd = nil
        case .requestingControl:
            cmd = .requestControl
        case .starting:
            cmd = .startOrResume
        case .ready:
            cmd = setpointCommand(now: now)
        }
        if let cmd {
            inFlight = (cmd, now)
            if phase == .ready { lastSentAt = now }
        }
        return cmd
    }

    private mutating func setpointCommand(now: Double) -> FTMSCommand? {
        guard now - lastSentAt >= minInterval else { return nil }
        let changed = significantlyDifferent(target, lastSent)
        let stale = now - lastSentAt >= refreshInterval && target != .none
        guard changed || stale else { return nil }
        let t = target
        lastSent = t
        switch t {
        case .none:
            return nil
        case .simulation(let g, let crr, let cw):
            return .setSimulation(gradePercent: g, windSpeed: 0, crr: crr, windResistance: cw)
        case .erg(let w):
            return .setTargetPower(watts: w)
        }
    }

    private func significantlyDifferent(_ a: TrainerTarget, _ b: TrainerTarget) -> Bool {
        switch (a, b) {
        case (.none, .none): return false
        case (.simulation(let g1, _, _), .simulation(let g2, _, _)): return abs(g1 - g2) >= 0.1
        case (.erg(let w1), .erg(let w2)): return abs(w1 - w2) >= 1
        default: return true
        }
    }

    public mutating func handle(_ response: FTMSControlResponse, now: Double) {
        guard let f = inFlight, f.command.opcode == response.requestOpcode else { return }
        inFlight = nil
        switch response.result {
        case .success:
            lastError = nil
            switch phase {
            case .requestingControl: phase = .starting
            case .starting: phase = .ready
            default: break
            }
        case .controlNotPermitted:
            // Someone else (or a reset) took control: ask again.
            lastError = "Trainern nekade styrning – försöker igen"
            phase = .requestingControl
            lastSent = .none
            retryAfter = now + 1
        case .notSupported where response.requestOpcode == FTMSCommand.startOrResume.opcode:
            // Many trainers don't implement start/resume; that's fine.
            phase = .ready
        default:
            lastError = "Trainern svarade med fel på kommando 0x\(String(response.requestOpcode, radix: 16))"
            if phase == .requestingControl { retryAfter = now + 2 }
            if phase == .starting { phase = .ready }
            if phase == .ready { lastSent = .none; retryAfter = now + 1 }
        }
    }
}
