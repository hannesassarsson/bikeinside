import BikeinsideCore
import Foundation
import Observation

/// Supabase project used for live multiplayer (Realtime broadcast only – no
/// database tables are read or written). The publishable key is meant to ship
/// inside client apps.
enum MultiplayerConfig {
    static let projectURL = "https://vqimjctsfgncertfzqtp.supabase.co"
    static let publishableKey = "sb_publishable_96sOYIhhPFIIBxeGLgJRdg_TqvNUwiy"

    /// Stable anonymous id for this installation.
    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "multiplayerId") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "multiplayerId")
        return id
    }
}

/// Joins a room for the current route, broadcasts our position ~2×/s and
/// collects everyone else's. Reconnects automatically.
@MainActor
@Observable
final class MultiplayerClient: NSObject {
    enum Status: Equatable {
        case off
        case connecting
        case online
        case error(String)

        var label: String {
            switch self {
            case .off: return "Offline"
            case .connecting: return "Ansluter…"
            case .online: return "Online"
            case .error(let e): return "Fel: \(e)"
            }
        }
    }

    private(set) var status: Status = .off
    let id = MultiplayerConfig.deviceId
    let topic: String

    @ObservationIgnored private var store = RemoteRiderStore()
    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var ref = 1
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectDelay: Double = 1
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var lastSent: Double = 0
    @ObservationIgnored var onCheer: ((Cheer) -> Void)?
    @ObservationIgnored var onRace: ((RaceAnnouncement) -> Void)?
    @ObservationIgnored var onFinish: ((RaceFinish) -> Void)?

    init(routeId: String, room: String) {
        topic = RealtimeProtocol.topic(routeId: routeId, room: room)
        super.init()
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func start() {
        stopped = false
        connect()
    }

    func stop() {
        stopped = true
        heartbeatTask?.cancel()
        if let task {
            send(RealtimeProtocol.leave(topic: topic, ref: nextRef()))
            task.cancel(with: .goingAway, reason: nil)
        }
        task = nil
        session?.invalidateAndCancel()
        session = nil
        status = .off
    }

    /// Other riders on `routeId`, extrapolated to now.
    func riders(routeId: String) -> [RemoteRiderState] {
        store.prune(now: now)
        return store.riders(routeId: routeId, now: now).filter { $0.id != id }
    }

    var onlineCount: Int { store.count }

    /// Broadcast our state (rate-limited to 2 Hz).
    func publish(_ state: RemoteRiderState) {
        guard status == .online, now - lastSent >= 0.5 else { return }
        lastSent = now
        send(RealtimeProtocol.broadcast(topic: topic, state: state, ref: nextRef()))
    }

    func sendCheer(_ text: String, name: String) {
        guard status == .online else { return }
        send(RealtimeProtocol.broadcast(topic: topic, event: "cheer", value: Cheer(from: id, name: name, text: text), ref: nextRef()))
    }

    func sendRace(_ race: RaceAnnouncement) {
        guard status == .online else { return }
        send(RealtimeProtocol.broadcast(topic: topic, event: "race", value: race, ref: nextRef()))
    }

    func sendFinish(_ f: RaceFinish) {
        guard status == .online else { return }
        send(RealtimeProtocol.broadcast(topic: topic, event: "finish", value: f, ref: nextRef()))
    }

    // MARK: Connection

    private func nextRef() -> Int {
        ref += 1
        return ref
    }

    private func connect() {
        guard !stopped, let url = RealtimeProtocol.websocketURL(projectURL: MultiplayerConfig.projectURL, apiKey: MultiplayerConfig.publishableKey) else { return }
        status = .connecting
        let s = URLSession(configuration: .default)
        session = s
        let t = s.webSocketTask(with: url)
        task = t
        t.resume()
        ref = 1
        send(RealtimeProtocol.join(topic: topic, presenceKey: id, ref: 1))
        receive(on: t)
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, !Task.isCancelled else { return }
                self.send(RealtimeProtocol.heartbeat(ref: self.nextRef()))
            }
        }
    }

    private func send(_ text: String) {
        task?.send(.string(text)) { _ in }
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: t)
                case .failure(let error):
                    self.connectionLost(error.localizedDescription)
                }
            }
        }
    }

    private func handle(_ text: String) {
        switch RealtimeProtocol.decode(text) {
        case .joined:
            status = .online
            reconnectDelay = 1
        case .joinFailed(let reason):
            status = .error(reason)
        case .state(let s):
            if s.id != id { store.update(s, now: now) }
        case .left(let leftId):
            store.remove(id: leftId)
        case .cheer(let c):
            if c.from != id { onCheer?(c) }
        case .race(let r):
            onRace?(r)
        case .finish(let f):
            if f.id != id { onFinish?(f) }
        case .other:
            break
        }
    }

    private func connectionLost(_ reason: String) {
        heartbeatTask?.cancel()
        task = nil
        guard !stopped else { return }
        status = .error("tappade anslutningen – försöker igen")
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.connect()
        }
    }
}
