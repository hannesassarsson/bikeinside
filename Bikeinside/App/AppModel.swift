import BikeinsideCore
import Foundation
import Observation

/// Top-level app state: profile, settings, history, Bluetooth and the active ride.
@MainActor
@Observable
final class AppModel {
    enum Screen {
        case home
        case ride(RideController)
        case summary(RideRecord, isNew: Bool, update: Progression.Update?)
    }

    enum Section: String, CaseIterable, Identifiable {
        case ride, workouts, history, devices, profile
        var id: String { rawValue }

        var title: String {
            switch self {
            case .ride: return "Cykla"
            case .workouts: return "Träningspass"
            case .history: return "Historik"
            case .devices: return "Enheter"
            case .profile: return "Profil & inställningar"
            }
        }

        var symbol: String {
            switch self {
            case .ride: return "bicycle"
            case .workouts: return "chart.bar.xaxis"
            case .history: return "clock.arrow.circlepath"
            case .devices: return "antenna.radiowaves.left.and.right"
            case .profile: return "person.crop.circle"
            }
        }
    }

    private let storage = Storage()
    let bluetooth = BluetoothManager()

    var screen: Screen = .home
    var section: Section = .ride

    var profile: RiderProfile { didSet { if profile != oldValue { storage.save(profile, to: "profile.json") } } }
    var settings: AppSettings { didSet { if settings != oldValue { storage.save(settings, to: "settings.json") } } }
    var personalBests: [String: Double] { didSet { storage.save(personalBests, to: "personal-bests.json") } }
    var importedWorkouts: [Workout] { didSet { storage.save(importedWorkouts, to: "workouts.json") } }
    private(set) var history: [RideRecord]
    private(set) var progression: Progression { didSet { storage.save(progression, to: "progression.json") } }

    var selectedRouteId: String = RouteLibrary.all[0].id
    /// nil = free ride
    var selectedWorkoutId: String?
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "onboarded") }
    }

    /// Built routes are cached; building is cheap but not free.
    private var routeCache: [String: Route] = [:]

    init() {
        profile = (storage.load(RiderProfile.self, from: "profile.json") ?? .default).sanitized()
        settings = storage.load(AppSettings.self, from: "settings.json") ?? AppSettings()
        personalBests = storage.load([String: Double].self, from: "personal-bests.json") ?? [:]
        importedWorkouts = storage.load([Workout].self, from: "workouts.json") ?? []
        let store = Storage()
        let rides = store.loadRideIndex()
        history = rides
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "onboarded")
        progression = store.load(Progression.self, from: "progression.json")
            ?? Progression.rebuild(from: rides, allRouteIds: RouteLibrary.all.map(\.id))
    }

    var allWorkouts: [Workout] { WorkoutLibrary.all + importedWorkouts }

    var selectedWorkout: Workout? {
        selectedWorkoutId.flatMap { id in allWorkouts.first { $0.id == id } }
    }

    func route(id: String) -> Route {
        if let r = routeCache[id] { return r }
        let bp = RouteLibrary.blueprint(id: id) ?? RouteLibrary.all[0]
        let r = RouteBuilder.build(bp)
        routeCache[id] = r
        return r
    }

    var isRiding: Bool {
        if case .ride = screen { return true }
        return false
    }

    // MARK: Ride lifecycle

    func startRide() {
        guard !isRiding else { return }
        let route = route(id: selectedRouteId)
        profile = profile.sanitized()
        let mode: RideMode = selectedWorkout.map { .workout($0) } ?? .freeRide
        let bots = settings.paceGroup == .none ? [] : BotProfile.group(
            wattsPerKg: settings.paceGroup.wattsPerKg, count: settings.paceGroup.riderCount,
            seed: UInt64(Date().timeIntervalSince1970))
        let config = RideEngine.Configuration(
            route: route, rider: profile, mode: mode, trainerDifficulty: settings.trainerDifficulty,
            ergEnabled: settings.ergEnabled, bots: bots, personalBests: personalBests, autoPause: settings.autoPause,
            powerSmoothing: settings.powerSmoothing, ergProtection: settings.ergProtection)
        let controller = RideController(config: config, bluetooth: bluetooth, settings: settings)
        controller.onFinish = { [weak self] record in self?.finishRide(record) }
        screen = .ride(controller)
    }

    private func finishRide(_ record: RideRecord?) {
        var workoutCompleted = false
        if case .ride(let c) = screen {
            workoutCompleted = c.engine.workoutStatus?.isFinished == true
            personalBests.merge(c.engine.personalBests) { min($0, $1) }
            settings.cameraMode = c.cameraMode
        }
        bluetooth.setTrainerTarget(.none)
        guard let record, record.stats.duration >= 30 else {
            screen = .home
            return
        }
        history.insert(record.withoutSamples, at: 0)
        storage.saveRide(record, index: history)
        let update = progression.apply(record, workoutCompleted: workoutCompleted, allRouteIds: RouteLibrary.all.map(\.id))
        screen = .summary(record, isNew: true, update: update)
    }

    func openRide(_ summary: RideRecord) {
        guard let full = storage.loadRide(id: summary.id) else { return }
        screen = .summary(full, isNew: false, update: nil)
    }

    func deleteRide(_ ride: RideRecord) {
        history.removeAll { $0.id == ride.id }
        storage.deleteRide(id: ride.id, index: history)
        if case .summary(let r, _, _) = screen, r.id == ride.id { screen = .home }
    }

    func closeSummary() {
        screen = .home
        section = .history
    }

    func applyFTP(_ ftp: Double) {
        profile.ftp = ftp
        profile = profile.sanitized()
    }

    func importWorkout(from url: URL) throws -> Workout {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        let w = try WorkoutFileParser.parse(text: text, fallbackName: url.deletingPathExtension().lastPathComponent)
        importedWorkouts.removeAll { $0.id == w.id }
        importedWorkouts.append(w)
        return w
    }

    func removeImportedWorkout(_ w: Workout) {
        importedWorkouts.removeAll { $0.id == w.id }
        if selectedWorkoutId == w.id { selectedWorkoutId = nil }
    }

    // MARK: Totals for the home screen

    var totalDistanceKm: Double { history.reduce(0) { $0 + $1.stats.distance } / 1000 }
    var totalHours: Double { Double(history.reduce(0) { $0 + $1.stats.duration }) / 3600 }
}

extension RideRecord {
    var withoutSamples: RideRecord {
        var r = self
        r.samples = []
        return r
    }
}
