import Foundation

/// Computer-controlled rider that shares the road.
public struct BotProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var weightKg: Double
    public var heightCm: Double
    public var wattsPerKg: Double
    public var jerseyColorIndex: Int

    public init(id: String, name: String, weightKg: Double, heightCm: Double, wattsPerKg: Double, jerseyColorIndex: Int) {
        self.id = id
        self.name = name
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.wattsPerKg = wattsPerKg
        self.jerseyColorIndex = jerseyColorIndex
    }

    /// Pace groups offered on the start screen.
    public static func group(wattsPerKg: Double, count: Int, seed: UInt64) -> [BotProfile] {
        let names = ["Astrid", "Bosse", "Cecilia", "Dag", "Ebba", "Fredrik", "Greta", "Hugo", "Ingrid", "Johan", "Karin", "Lars", "Maja", "Nils", "Olivia", "Per"]
        var rng = SeededRandom(seed: seed)
        // unique names: shuffle once, then take in order
        var pool = names
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            pool.swapAt(i, Int(rng.unit() * Double(i + 1)) % (i + 1))
        }
        return (0..<count).map { k in
            let w = rng.range(58, 88)
            let jitter = rng.range(-0.15, 0.15)
            return BotProfile(
                id: "bot-\(seed)-\(k)", name: pool[k % pool.count],
                weightKg: w, heightCm: 160 + (w - 55) * 0.9 + rng.range(-5, 5),
                wattsPerKg: max(1.0, wattsPerKg + jitter), jerseyColorIndex: Int(rng.unit() * 8) % 8)
        }
    }
}

public enum RideMode: Sendable, Equatable {
    case freeRide
    case workout(Workout)
}

public enum RideEvent: Equatable, Sendable {
    case segmentStarted(RouteSegment)
    case segmentFinished(SegmentResult)
    case lapCompleted(lap: Int, seconds: Double)
    case workoutStep(index: Int, step: WorkoutStep)
    case workoutFinished
    case kilometer(Int)
}

/// The simulation: integrates rider and bot physics along the route, runs the
/// workout clock, times segments and records 1 Hz samples. Deterministic and
/// UI-free; the app calls `tick` every frame and reads the public state.
public final class RideEngine {
    public struct Configuration: Sendable {
        public var route: Route
        public var rider: RiderProfile
        public var mode: RideMode
        /// 0…1 scale applied to the grade sent to the trainer (road feel only; speed always uses real grade).
        public var trainerDifficulty: Double
        public var ergEnabled: Bool
        public var bots: [BotProfile]
        /// Best known times per segment id, for PR detection.
        public var personalBests: [String: Double]
        public var autoPause: Bool
        /// Seconds of averaging for the displayed power (1, 3 or 5 are typical).
        public var powerSmoothing: Double
        /// Protects the rider in ERG: soft start, gentle ramps, and backing off when cadence collapses.
        public var ergProtection: Bool
        /// Fastest previous lap on this route, replayed as a ghost.
        public var ghost: GhostTrack?

        public init(
            route: Route, rider: RiderProfile, mode: RideMode = .freeRide, trainerDifficulty: Double = 0.5,
            ergEnabled: Bool = true, bots: [BotProfile] = [], personalBests: [String: Double] = [:], autoPause: Bool = true,
            powerSmoothing: Double = 3, ergProtection: Bool = true, ghost: GhostTrack? = nil
        ) {
            self.route = route
            self.rider = rider
            self.mode = mode
            self.trainerDifficulty = trainerDifficulty
            self.ergEnabled = ergEnabled
            self.bots = bots
            self.personalBests = personalBests
            self.autoPause = autoPause
            self.powerSmoothing = powerSmoothing
            self.ergProtection = ergProtection
            self.ghost = ghost
        }
    }

    /// Why the ERG target currently differs from the workout target (for the HUD).
    public enum ErgAdjustment: Equatable, Sendable {
        case none
        case softStart
        case ramping
        case lowCadence
    }

    public struct Bot: Sendable {
        public var profile: BotProfile
        public var distance: Double
        public var speed: Double
        public var power: Double
        /// Metres right of the road centre.
        public var lateral: Double
        var preferredLane: Double
        var params: PhysicsParameters
        var phase: Double
    }

    public struct WorkoutStatus: Sendable {
        public var workout: Workout
        public var elapsed: Double
        public var stepIndex: Int?
        public var elapsedInStep: Double
        public var remainingInStep: Double
        public var targetWatts: Double?
        public var nextStep: WorkoutStep?
        public var isFinished: Bool
    }

    public private(set) var config: Configuration
    public var route: Route { config.route }

    // Rider state
    public private(set) var distance: Double = 0
    public private(set) var speed: Double = 0
    public private(set) var power: Double = 0
    public private(set) var cadence: Double?
    public private(set) var heartRate: Int?
    public private(set) var grade: Double = 0
    public private(set) var draftFactor: Double = 1
    public private(set) var ascent: Double = 0
    public private(set) var kilojoules: Double = 0
    /// Wall-clock time since start, excluding manual pauses.
    public private(set) var elapsed: Double = 0
    /// Moving time (excludes auto-pause).
    public private(set) var timerTime: Double = 0
    public private(set) var isAutoPaused = false
    public var isPaused = false
    public let riderLateral: Double = 1.0

    public private(set) var bots: [Bot] = []
    public private(set) var samples: [RideSample] = []
    public private(set) var segmentResults: [SegmentResult] = []
    public private(set) var lapCount = 0

    /// Workout intensity multiplier the rider can nudge (+/- 5 %).
    public var workoutIntensity: Double = 1.0 {
        didSet { workoutIntensity = Interp.clamp(workoutIntensity, 0.5, 1.5) }
    }
    public private(set) var workoutElapsed: Double = 0

    private var params: PhysicsParameters
    private var events: [RideEvent] = []
    private var stillTime = 0.0
    private var lastElevation: Double
    private var nextSampleAt = 0.0
    private var lapStartTimer = 0.0
    private var activeSegments: [String: (startTimer: Double, startKJ: Double)] = [:]
    private var lastWorkoutStep: Int?
    private var workoutDone = false
    private var powerHistory: [(t: Double, p: Double)] = []
    /// ERG power actually sent to the trainer (after protection), nil when not in ERG.
    public private(set) var ergCommand: Double?
    public private(set) var ergAdjustment: ErgAdjustment = .none
    private var lapStartDistance = 0.0
    private var trace = LapTraceRecorder()
    /// Traces of every lap completed this ride (candidates for a new ghost).
    public private(set) var completedLaps: [GhostTrack] = []
    private var lowCadenceTime = 0.0
    private var cadenceGuardActive = false

    public init(config: Configuration) {
        self.config = config
        self.params = PhysicsParameters(rider: config.rider, crr: config.route.surface.crr)
        self.lastElevation = config.route.sample(at: 0).elevation
        var rng = SeededRandom(seed: 4242)
        let lanes = [-1.6, -0.4, 0.4, 1.6, 2.4, -2.4]
        bots = config.bots.enumerated().map { k, profile in
            let p = PhysicsParameters(totalMass: profile.weightKg + 8, cda: RiderProfile(weightKg: profile.weightKg, heightCm: profile.heightCm).cda)
            // spread around the start: some ahead to chase, a few behind
            let start = rng.range(-40, 160)
            let lane = lanes[k % lanes.count]
            return Bot(profile: profile, distance: max(0, start) + Double(k) * 3, speed: 0, power: 0,
                       lateral: lane, preferredLane: lane, params: p, phase: rng.range(0, 100))
        }
    }

    // MARK: Public API

    public func drainEvents() -> [RideEvent] {
        defer { events.removeAll() }
        return events
    }

    /// Current position on the road (wrapped for loops).
    public var routeSample: RouteSample { route.sample(at: distance) }

    /// Rolling average power over `powerSmoothing` seconds, as shown in the HUD.
    public var power3s: Double {
        let window = max(config.powerSmoothing, 0.01)
        let recent = powerHistory.filter { elapsed - $0.t < window }
        guard !recent.isEmpty else { return power }
        return recent.reduce(0) { $0 + $1.p } / Double(recent.count)
    }

    public var wattsPerKg: Double { power3s / max(config.rider.weightKg, 1) }

    public var workoutStatus: WorkoutStatus? {
        guard case .workout(let w) = config.mode else { return nil }
        let pos = w.position(at: workoutElapsed)
        let target = w.targetWatts(at: workoutElapsed, ftp: config.rider.ftp).map { $0 * workoutIntensity }
        let next = pos.flatMap { $0.index + 1 < w.steps.count ? w.steps[$0.index + 1] : nil }
        return WorkoutStatus(
            workout: w, elapsed: workoutElapsed, stepIndex: pos?.index, elapsedInStep: pos?.elapsedInStep ?? 0,
            remainingInStep: pos?.remainingInStep ?? 0, targetWatts: target, nextStep: next, isFinished: pos == nil)
    }

    /// What the trainer should do this instant.
    public var trainerTarget: TrainerTarget {
        if config.ergEnabled, let ws = workoutStatus, !ws.isFinished, let t = ws.targetWatts {
            let watts = config.ergProtection ? (ergCommand ?? t) : t
            return .erg(watts: Int(watts.rounded()))
        }
        let rho = CyclingPhysics.airDensity(altitude: routeSample.elevation)
        let cw = 0.5 * rho * params.cda * draftFactor
        let g = grade * 100 * Interp.clamp(config.trainerDifficulty, 0, 1)
        return .simulation(gradePercent: Interp.clamp(g, -15, 20), crr: params.crr, windResistance: cw)
    }

    public func skipWorkoutStep() {
        guard let ws = workoutStatus, let i = ws.stepIndex else { return }
        workoutElapsed = ws.workout.startTime(ofStep: i + 1)
    }

    public func updateRider(_ rider: RiderProfile) {
        config.rider = rider
        params = PhysicsParameters(rider: rider, crr: config.route.surface.crr)
    }

    public func setTrainerDifficulty(_ d: Double) { config.trainerDifficulty = Interp.clamp(d, 0, 1) }
    public func setErgEnabled(_ on: Bool) { config.ergEnabled = on }
    public func setPowerSmoothing(_ seconds: Double) { config.powerSmoothing = Interp.clamp(seconds, 0.5, 10) }

    // MARK: Simulation

    public func tick(dt rawDt: Double, inputs: RideInputs) {
        guard rawDt > 0, !isPaused else { return }
        let dt = min(rawDt, 0.25)
        let p = max(0, inputs.power ?? 0)
        power = p
        cadence = inputs.cadence
        heartRate = inputs.heartRate
        elapsed += dt

        // Auto-pause when stopped and not pedalling.
        if config.autoPause && p < 1 && speed < 0.3 { stillTime += dt } else { stillTime = 0 }
        isAutoPaused = config.autoPause && stillTime > 3

        // Player physics
        let here = route.sample(at: distance)
        grade = here.grade
        params.airDensity = CyclingPhysics.airDensity(altitude: here.elevation)
        draftFactor = Drafting.dragFactor(position: distance, others: bots.map(\.distance) + remoteRiders.map(\.effectiveDistance), loopLength: nil)
        speed = CyclingPhysics.step(speed: speed, power: p, grade: grade, dt: dt, params: params, draftFactor: draftFactor)
        let previous = distance
        distance += speed * dt
        kilojoules += p * dt / 1000

        let there = route.sample(at: distance)
        if there.elevation > lastElevation { ascent += there.elevation - lastElevation }
        lastElevation = there.elevation

        if !isAutoPaused {
            timerTime += dt
            if case .workout = config.mode { workoutElapsed += dt }
        }

        powerHistory.append((elapsed, p))
        while let f = powerHistory.first, elapsed - f.t > 10 { powerHistory.removeFirst() }

        updateErg(dt: dt)

        trace.add(lapTime: timerTime - lapStartTimer, lapDistance: distance - lapStartDistance)
        updateSegments(from: previous, to: distance)
        updateWorkout()
        updateBots(dt: dt)
        record()
    }

    /// ERG protection: soft start over the first 20 s, upward changes ramped at
    /// 40 W/s (downward instant), and a 30 % back-off while cadence is below 55 rpm
    /// so the rider can spin back up instead of grinding to a halt.
    private func updateErg(dt: Double) {
        guard config.ergEnabled, let ws = workoutStatus, !ws.isFinished, let target = ws.targetWatts else {
            ergCommand = nil
            ergAdjustment = .none
            return
        }
        guard config.ergProtection else {
            ergCommand = target
            ergAdjustment = .none
            return
        }
        var goal = target
        var reason = ErgAdjustment.none
        if workoutElapsed < 20 {
            goal = target * (0.5 + 0.5 * workoutElapsed / 20)
            reason = .softStart
        }
        if let c = cadence {
            if c < 55 && !isAutoPaused { lowCadenceTime += dt } else if c > 70 { lowCadenceTime = 0 }
            if lowCadenceTime > 2 { cadenceGuardActive = true }
            if cadenceGuardActive && c > 70 { cadenceGuardActive = false }
        }
        if cadenceGuardActive && target > 0.5 * config.rider.ftp {
            goal = min(goal, target * 0.7)
            reason = .lowCadence
        }
        let current = ergCommand ?? goal
        if goal > current {
            ergCommand = min(goal, current + 40 * dt)
            if reason == .none && goal - ergCommand! > 1 { reason = .ramping }
        } else {
            ergCommand = goal
        }
        ergAdjustment = reason
    }

    private func crossed(_ mark: Double, from a: Double, to b: Double) -> Bool {
        guard b > a else { return false }
        let L = route.length
        let k = (b / L).rounded(.down)
        for m in [k * L + mark, (k - 1) * L + mark] where m > a && m <= b { return true }
        return false
    }

    private func updateSegments(from a: Double, to b: Double) {
        if crossed(0, from: a, to: b) {
            lapCount += 1
            let lapSeconds = timerTime - lapStartTimer
            events.append(.lapCompleted(lap: lapCount, seconds: lapSeconds))
            let marks = Int(route.length / trace.step) + 1
            if trace.times.count >= marks {
                completedLaps.append(GhostTrack(routeId: route.id, lapSeconds: lapSeconds, step: trace.step,
                                                times: Array(trace.times.prefix(marks))))
            }
            lapStartTimer = timerTime
            lapStartDistance += route.length
            trace.reset()
        }
        if Int(b / 1000) > Int(a / 1000) { events.append(.kilometer(Int(b / 1000))) }
        for seg in route.segments {
            if crossed(seg.startDistance, from: a, to: b) {
                activeSegments[seg.id] = (timerTime, kilojoules)
                events.append(.segmentStarted(seg))
            }
            if crossed(seg.endDistance, from: a, to: b), let st = activeSegments.removeValue(forKey: seg.id) {
                let secs = max(timerTime - st.startTimer, 0.1)
                let avg = (kilojoules - st.startKJ) * 1000 / secs
                let pb = config.personalBests[seg.id]
                let isPB = pb.map { secs < $0 } ?? true
                if isPB { config.personalBests[seg.id] = secs }
                let r = SegmentResult(segmentId: seg.id, name: seg.name, kind: seg.kind, seconds: secs, averagePower: avg, isPersonalBest: isPB)
                segmentResults.append(r)
                events.append(.segmentFinished(r))
            }
        }
    }

    /// Segment currently being ridden, with progress 0…1.
    public var activeSegment: (segment: RouteSegment, progress: Double, seconds: Double)? {
        let d = route.normalize(distance)
        for seg in route.segments {
            if let st = activeSegments[seg.id], d >= seg.startDistance, d < seg.endDistance {
                return (seg, (d - seg.startDistance) / seg.length, timerTime - st.startTimer)
            }
        }
        return nil
    }

    private func updateWorkout() {
        guard let ws = workoutStatus else { return }
        if ws.isFinished {
            if !workoutDone {
                workoutDone = true
                events.append(.workoutFinished)
            }
            return
        }
        if let i = ws.stepIndex, i != lastWorkoutStep {
            lastWorkoutStep = i
            events.append(.workoutStep(index: i, step: ws.workout.steps[i]))
        }
    }

    private func updateBots(dt: Double) {
        guard !bots.isEmpty else { return }
        let positions = bots.map(\.distance) + [distance]
        for i in bots.indices {
            var b = bots[i]
            b.phase += dt
            let s = route.sample(at: b.distance)
            let base = b.profile.wattsPerKg * b.profile.weightKg
            // push harder on climbs, ease off on descents like real riders do
            let terrain = 1 + 0.22 * Interp.clamp(s.grade / 0.08, -0.7, 1)
            let seed = Double(i) * 1.7
            let wobble = 1 + 0.05 * sin(b.phase * 0.13 + seed) + 0.025 * sin(b.phase * 0.71 + seed * 2)
            b.power = max(0, base * terrain * wobble)
            var others = positions
            others.remove(at: i)
            b.params.airDensity = CyclingPhysics.airDensity(altitude: s.elevation)
            let draft = Drafting.dragFactor(position: b.distance, others: others, loopLength: nil)
            b.speed = CyclingPhysics.step(speed: b.speed, power: b.power, grade: s.grade, dt: dt, params: b.params, draftFactor: draft)
            b.distance += b.speed * dt

            // Steer around the player when overlapping longitudinally.
            var lane = b.preferredLane
            if abs(b.distance - distance) < 4 && abs(lane - riderLateral) < 1.0 {
                lane = riderLateral + (lane >= riderLateral ? 1.2 : -1.2)
            }
            lane = Interp.clamp(lane, -2.8, 2.8)
            b.lateral += (lane - b.lateral) * Interp.damp(rate: 1.5, dt: dt)
            bots[i] = b
        }
    }

    private func record() {
        while timerTime >= nextSampleAt {
            let s = route.sample(at: distance)
            samples.append(RideSample(
                t: Int(nextSampleAt), power: Int(power.rounded()), heartRate: heartRate,
                cadence: cadence.map { Int($0.rounded()) }, speed: speed, distance: distance,
                elevation: s.elevation, grade: s.grade))
            nextSampleAt += 1
        }
    }

    /// Riders sorted by gap to the player (positive = ahead), for the HUD.
    public struct LeaderboardRow: Equatable, Sendable {
        public var name: String
        public var gapMeters: Double
        public var gapSeconds: Double
        public var wattsPerKg: Double
        public var isPlayer: Bool
        /// A real person riding online (not a bot).
        public var isRemote: Bool
    }

    public func leaderboard() -> [LeaderboardRow] {
        let pace = max(speed, 3)
        var rows = bots.map { b in
            let gap = b.distance - distance
            return LeaderboardRow(name: b.profile.name, gapMeters: gap, gapSeconds: gap / pace,
                                  wattsPerKg: b.power / b.profile.weightKg, isPlayer: false, isRemote: false)
        }
        for r in remoteRiders {
            let gap = r.effectiveDistance - distance
            rows.append(LeaderboardRow(name: r.state.name, gapMeters: gap, gapSeconds: gap / pace,
                                       wattsPerKg: r.state.wattsPerKg, isPlayer: false, isRemote: true))
        }
        rows.append(LeaderboardRow(name: config.rider.name, gapMeters: 0, gapSeconds: 0, wattsPerKg: wattsPerKg, isPlayer: true, isRemote: false))
        return rows.sorted { $0.gapMeters > $1.gapMeters }
    }

    // MARK: Ghost

    private var lapTime: Double { timerTime - lapStartTimer }

    /// Ghost position in this rider's distance frame, if racing a ghost on this route.
    public var ghostDistance: Double? {
        guard let g = config.ghost, g.routeId == route.id else { return nil }
        return lapStartDistance + g.distance(atTime: lapTime)
    }

    /// Seconds ahead (+) or behind (−) the ghost at the current point of the lap.
    public var ghostGapSeconds: Double? {
        guard let g = config.ghost, g.routeId == route.id else { return nil }
        let lapDistance = distance - lapStartDistance
        return g.time(atDistance: lapDistance) - lapTime
    }

    /// The fastest lap of this ride, if it beats `existing`.
    public func bestLap(beating existing: GhostTrack?) -> GhostTrack? {
        guard let best = completedLaps.min(by: { $0.lapSeconds < $1.lapSeconds }) else { return nil }
        if let e = existing, e.routeId == best.routeId, e.lapSeconds <= best.lapSeconds { return nil }
        return best
    }

    // MARK: Online riders

    public struct Remote: Sendable {
        public var state: RemoteRiderState
        /// Their position expressed in this rider's distance frame (closest lap).
        public var effectiveDistance: Double
        /// Metres right of the road centre (assigned so riders don't overlap).
        public var lateral: Double
    }

    public private(set) var remoteRiders: [Remote] = []

    /// Online riders on the same route; positions are mapped onto the nearest
    /// lap so someone a lap ahead still shows up next to you if you're close.
    public func setRemoteRiders(_ riders: [RemoteRiderState]) {
        let L = route.length
        let mine = route.normalize(distance)
        let lanes = [-0.8, 0.2, -1.8, 2.0, -2.6, 1.4]
        remoteRiders = riders.enumerated().map { k, s in
            var gap = route.normalize(s.distance) - mine
            if route.isLoop {
                if gap > L / 2 { gap -= L }
                if gap < -L / 2 { gap += L }
            }
            return Remote(state: s, effectiveDistance: distance + gap, lateral: lanes[k % lanes.count])
        }
    }

    /// Payload this rider broadcasts.
    public func broadcastState(id: String) -> RemoteRiderState {
        RemoteRiderState(id: id, name: config.rider.name, jersey: config.rider.jerseyColorIndex, heightCm: config.rider.heightCm,
                         routeId: route.id, distance: distance, speed: speed, power: power3s, wattsPerKg: wattsPerKg, cadence: cadence)
    }

    /// Packages the ride for saving and export.
    public func finish(startDate: Date) -> RideRecord {
        let stats = RideStats.compute(samples: samples, ftp: config.rider.ftp)
        var ftpEstimate: Double?
        var workoutName: String?
        if case .workout(let w) = config.mode {
            workoutName = w.name
            if let test = w.test {
                let needed = test == .ramp ? 60 : 1200
                if samples.count >= needed { ftpEstimate = RideStats.ftpEstimate(test: test, samples: samples) }
            }
        }
        return RideRecord(
            startDate: startDate, routeId: route.id, routeName: route.name, workoutName: workoutName,
            riderWeightKg: config.rider.weightKg, ftp: config.rider.ftp, elapsedSeconds: Int(elapsed),
            stats: stats, segments: segmentResults, ftpEstimate: ftpEstimate, samples: samples)
    }

    /// Personal bests including any set during this ride.
    public var personalBests: [String: Double] { config.personalBests }
}
