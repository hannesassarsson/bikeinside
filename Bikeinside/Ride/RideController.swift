import BikeinsideCore
import Foundation
import Observation
import SwiftUI

/// Values shown in the ride HUD, refreshed ~10 times per second.
struct HUDState {
    var power: Double = 0
    var power3s: Double = 0
    var wattsPerKg: Double = 0
    var heartRate: Int?
    var cadence: Double?
    var speedKmh: Double = 0
    var distance: Double = 0
    var timerTime: Double = 0
    var grade: Double = 0
    var elevation: Double = 0
    var ascent: Double = 0
    var draftFactor: Double = 1
    var lap = 0
    var routeFraction: Double = 0
    var isAutoPaused = false
    var powerSource: SensorRole?
    var workout: RideEngine.WorkoutStatus?
    var segment: (segment: RouteSegment, progress: Double, seconds: Double)?
    var leaderboard: [RideEngine.LeaderboardRow] = []
    var botRouteFractions: [Double] = []
    var trainerMode: String = ""
    var ghostGap: Double?
    var ghostLapSeconds: Double?
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var title: String
    var subtitle: String
    var color: Color
    var created = Date()
}

/// Drives one ride: loads the world, ticks the engine every display frame,
/// talks to the trainer and publishes HUD state.
@MainActor
@Observable
final class RideController {
    let engine: RideEngine
    let bluetooth: BluetoothManager
    let startDate = Date()
    let ftp: Double
    let riderWeight: Double

    private(set) var world: WorldScene?
    private(set) var loadProgress: Double = 0
    private(set) var loadError: String?
    private(set) var hud = HUDState()
    private(set) var banners: [Banner] = []
    private(set) var isPaused = false
    var cameraMode: CameraMode
    var showEndConfirm = false
    var showHelp = false
    /// Keyboard-controlled power used when no power source is connected.
    var virtualPower: Double = 160
    /// In a workout without a power source, follow the target automatically.
    var virtualFollowsTarget = true
    var ergEnabled: Bool {
        didSet { engine.setErgEnabled(ergEnabled) }
    }
    var trainerDifficulty: Double {
        didSet { engine.setTrainerDifficulty(trainerDifficulty) }
    }

    @ObservationIgnored var onFinish: ((RideRecord?) -> Void)?
    @ObservationIgnored private var hudAccumulator = 0.0
    @ObservationIgnored private var trainerAccumulator = 0.0
    @ObservationIgnored private let showNames: Bool
    @ObservationIgnored private let weather: WeatherChoice
    /// Live multiplayer (nil when disabled in settings).
    let multiplayer: MultiplayerClient?
    @ObservationIgnored let coach: CoachAudio
    @ObservationIgnored private var race = RaceTracker()
    @ObservationIgnored private var lastCountdownSpoken: Int?
    /// Group race shown in the HUD.
    private(set) var racePhase: RaceTracker.Phase = .idle
    private(set) var raceResults: [RaceFinish] = []
    private(set) var raceRemaining: Double?
    private(set) var raceInfo: RaceAnnouncement?

    var usesVirtualPower: Bool { bluetooth.powerSource() == nil }

    init(config: RideEngine.Configuration, bluetooth: BluetoothManager, settings: AppSettings) {
        engine = RideEngine(config: config)
        self.bluetooth = bluetooth
        ftp = config.rider.ftp
        riderWeight = config.rider.weightKg
        cameraMode = settings.cameraMode
        ergEnabled = config.ergEnabled
        trainerDifficulty = config.trainerDifficulty
        showNames = settings.showRiderNames
        weather = settings.weather
        multiplayer = settings.multiplayerEnabled
            ? MultiplayerClient(routeId: config.route.id, room: settings.multiplayerRoom) : nil
        virtualPower = (config.rider.ftp * 0.65).rounded()
        coach = CoachAudio(voice: settings.voiceCoach, sounds: settings.soundEffects)
        multiplayer?.start()
        multiplayer?.onCheer = { [weak self] c in
            guard let self else { return }
            self.push(Banner(symbol: "hand.thumbsup.fill", title: "\(c.name): \(c.text)", subtitle: "Online", color: Theme.accentSecondary))
            self.coach.play("Pop")
        }
        multiplayer?.onRace = { [weak self] r in self?.acceptRace(r) }
        multiplayer?.onFinish = { [weak self] f in
            guard let self else { return }
            self.race.record(f)
            self.push(Banner(symbol: "flag.checkered", title: "\(f.name) i mål", subtitle: Format.duration(f.seconds), color: .white))
        }
        Task { await load() }
    }

    private func load() async {
        let route = engine.route
        let report: @Sendable (Double) -> Void = { [weak self] p in
            Task { @MainActor in self?.loadProgress = p }
        }
        let geometry = await Task.detached(priority: .userInitiated) {
            WorldBuilder.build(route: route, progress: report)
        }.value
        let rider = engine.config.rider
        let bots = engine.config.bots
        do {
            world = try WorldScene(route: route, geometry: geometry, rider: rider, bots: bots, showNames: showNames, weather: weather)
        } catch {
            loadError = "Kunde inte bygga 3D-världen: \(error.localizedDescription)"
            return
        }
        loadProgress = 1
        publishHUD()
        if case .workout(let w) = engine.config.mode {
            push(Banner(symbol: "figure.indoor.cycle", title: w.name, subtitle: "Börja trampa så startar passet", color: Theme.accent))
        } else {
            push(Banner(symbol: "flag.checkered", title: route.name, subtitle: "\(Format.km(route.length)) km · \(Int(route.totalAscent)) höjdmeter per varv", color: Theme.accentSecondary))
        }
    }

    var isLoaded: Bool { world != nil }

    // MARK: Frame loop

    func frame(dt: Double) {
        guard let world else { return }
        let dt = min(max(dt, 0), 0.1)
        var inputs = bluetooth.inputs()
        if inputs.power == nil {
            if virtualFollowsTarget, ergEnabled, let target = engine.workoutStatus?.targetWatts {
                virtualPower += (target - virtualPower) * Interp.damp(rate: 3, dt: dt)
            }
            inputs.power = isPaused ? 0 : virtualPower
            if inputs.cadence == nil { inputs.cadence = virtualPower > 0 ? 86 + sin(engine.elapsed * 0.4) * 4 : 0 }
        }
        engine.tick(dt: dt, inputs: inputs)
        world.update(engine: engine, dt: isPaused ? 0 : dt, cameraMode: cameraMode)

        if let mp = multiplayer {
            engine.setRemoteRiders(mp.riders(routeId: engine.route.id))
            if !isPaused { mp.publish(engine.broadcastState(id: mp.id)) }
        }
        updateRace()

        trainerAccumulator += dt
        if trainerAccumulator >= 0.1 {
            trainerAccumulator = 0
            bluetooth.setTrainerTarget(isPaused ? .none : engine.trainerTarget)
        }

        coach.update(engine: engine, paused: isPaused, ftp: ftp)
        for e in engine.drainEvents() {
            handle(e)
            coach.handle(e, route: engine.route)
        }

        hudAccumulator += dt
        if hudAccumulator >= 0.1 {
            hudAccumulator = 0
            publishHUD()
            banners.removeAll { Date().timeIntervalSince($0.created) > 5 }
        }
    }

    private func publishHUD() {
        var h = HUDState()
        h.power = engine.power
        h.power3s = engine.power3s
        h.wattsPerKg = engine.wattsPerKg
        h.heartRate = engine.heartRate
        h.cadence = engine.cadence
        h.speedKmh = engine.speed * 3.6
        h.distance = engine.distance
        h.timerTime = engine.timerTime
        h.grade = engine.grade
        h.elevation = engine.routeSample.elevation
        h.ascent = engine.ascent
        h.draftFactor = engine.draftFactor
        h.lap = engine.lapCount
        h.routeFraction = engine.route.normalize(engine.distance) / engine.route.length
        h.isAutoPaused = engine.isAutoPaused
        h.powerSource = bluetooth.powerSource()
        h.workout = engine.workoutStatus
        h.segment = engine.activeSegment
        h.leaderboard = engine.leaderboard()
        h.botRouteFractions = engine.bots.map { engine.route.normalize($0.distance) / engine.route.length }
        h.ghostGap = engine.ghostGapSeconds
        h.ghostLapSeconds = engine.config.ghost?.lapSeconds
        switch engine.trainerTarget {
        case .erg(let w): h.trainerMode = "ERG \(w) W"
        case .simulation(let g, _, _): h.trainerMode = "SIM \(Format.number(g, decimals: 1)) %"
        case .none: h.trainerMode = ""
        }
        hud = h
    }

    private func handle(_ e: RideEvent) {
        switch e {
        case .segmentStarted(let s):
            let grade = engine.route.averageGrade(from: s.startDistance, to: s.endDistance)
            push(Banner(
                symbol: s.kind == .climb ? "mountain.2.fill" : "bolt.fill",
                title: s.kind == .climb ? "Klättring: \(s.name)" : "Sprint: \(s.name)",
                subtitle: s.kind == .climb ? "\(Format.km(s.length, decimals: 1)) km · \(Format.percent(grade)) snitt" : "\(Int(s.length)) m – ge allt!",
                color: s.kind == .climb ? Theme.accent : Theme.good))
        case .segmentFinished(let r):
            push(Banner(
                symbol: r.isPersonalBest ? "trophy.fill" : "stopwatch",
                title: "\(r.name): \(Format.duration(r.seconds))",
                subtitle: (r.isPersonalBest ? "Nytt personbästa! " : "") + "\(Int(r.averagePower)) W snitt",
                color: r.isPersonalBest ? Theme.warn : .white))
        case .lapCompleted(let lap, let secs):
            push(Banner(symbol: "arrow.triangle.2.circlepath", title: "Varv \(lap) klart", subtitle: Format.duration(secs), color: Theme.accentSecondary))
        case .workoutStep(let index, let step):
            guard index > 0 else { return }
            let target = step.isFree ? "Kör efter känsla" : "\(Int(step.start.watts(ftp: ftp) * engine.workoutIntensity)) W"
            push(Banner(symbol: "chevron.forward.circle.fill", title: step.label, subtitle: "\(target) i \(Format.duration(step.duration))", color: Theme.zoneColor(power: step.start.watts(ftp: ftp), ftp: ftp)))
        case .workoutFinished:
            push(Banner(symbol: "checkmark.seal.fill", title: "Passet är klart!", subtitle: "Bra jobbat. Rulla vidare eller avsluta.", color: Theme.good))
        case .kilometer(let km):
            if km % 5 == 0 {
                push(Banner(symbol: "signpost.right.fill", title: "\(km) km", subtitle: Format.duration(engine.timerTime), color: .white))
            }
        }
    }

    func push(_ b: Banner) {
        banners.append(b)
        if banners.count > 3 { banners.removeFirst() }
    }

    // MARK: Group race

    private func acceptRace(_ r: RaceAnnouncement) {
        guard race.announce(r, routeId: engine.route.id, myId: multiplayer?.id ?? "me") else { return }
        raceInfo = r
        lastCountdownSpoken = nil
        push(Banner(symbol: "flag.checkered", title: "Lopp: \(Format.km(r.distance)) km",
                    subtitle: "\(r.starterName) startade ett lopp – start om \(Int(r.startAt - Date().timeIntervalSince1970)) s", color: Theme.warn))
        coach.say("\(r.starterName) har startat ett lopp på \(Format.km(r.distance)) kilometer.", priority: true)
    }

    /// Start a race for everyone in the room (and yourself) with a 15 s countdown.
    func startRace(distance: Double) {
        let r = RaceAnnouncement(raceId: UUID().uuidString, routeId: engine.route.id,
                                 startAt: Date().timeIntervalSince1970 + 15, distance: distance,
                                 starterName: engine.config.rider.name)
        multiplayer?.sendRace(r)
        acceptRace(r)
    }

    func sendCheer(_ text: String) {
        multiplayer?.sendCheer(text, name: engine.config.rider.name)
        push(Banner(symbol: "paperplane.fill", title: "Du: \(text)", subtitle: "Skickat till alla i rummet", color: Theme.accentSecondary))
    }

    func dismissRace() {
        race.clear()
        raceInfo = nil
        racePhase = .idle
        raceResults = []
    }

    private func updateRace() {
        guard raceInfo != nil else { return }
        let now = Date().timeIntervalSince1970
        if let mine = race.update(now: now, distance: engine.distance, myName: engine.config.rider.name) {
            multiplayer?.sendFinish(mine)
            coach.play("Hero")
            coach.say("I mål! \(CoachAudio.spokenDuration(mine.seconds)).", priority: true)
        }
        let phase = race.phase(now: now, distance: engine.distance)
        if case .countdown(let n) = phase, n != lastCountdownSpoken, n <= 10 {
            lastCountdownSpoken = n
            if n <= 5 { coach.play("Tink") }
            if n == 10 || n <= 3 { coach.say("\(n)", priority: true) }
        }
        if case .racing = phase, case .countdown = racePhase { coach.say("Kör!", priority: true) }
        racePhase = phase
        raceResults = race.results
        raceRemaining = race.remaining(distance: engine.distance)
    }

    // MARK: Controls

    func togglePause() {
        isPaused.toggle()
        engine.isPaused = isPaused
        bluetooth.setTrainerTarget(isPaused ? .none : engine.trainerTarget)
    }

    func requestEnd() {
        if !isPaused { togglePause() }
        showEndConfirm = true
    }

    func cancelEnd() {
        showEndConfirm = false
        if isPaused { togglePause() }
    }

    func finish(save: Bool) {
        multiplayer?.stop()
        coach.stop()
        showEndConfirm = false
        bluetooth.setTrainerTarget(.none)
        let record = engine.finish(startDate: startDate)
        onFinish?(save ? record : nil)
    }

    func adjustVirtualPower(_ delta: Double) {
        virtualFollowsTarget = false
        virtualPower = Interp.clamp(virtualPower + delta, 0, 1500)
    }

    func adjustIntensity(_ delta: Double) {
        engine.workoutIntensity += delta
        publishHUD()
    }

    func skipStep() {
        engine.skipWorkoutStep()
        publishHUD()
    }

    func cycleCamera() { cameraMode = cameraMode.next }
}
