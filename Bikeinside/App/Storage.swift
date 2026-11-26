import BikeinsideCore
import Foundation

/// User-adjustable app preferences.
struct AppSettings: Codable, Equatable {
    var trainerDifficulty: Double = 0.5
    var ergEnabled: Bool = true
    var autoPause: Bool = true
    var paceGroup: PaceGroup = .tempo
    var cameraMode: CameraMode = .chase
    var showRiderNames: Bool = true
}

enum PaceGroup: String, Codable, CaseIterable, Identifiable {
    case none, easy, tempo, fast, race

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Ensam"
        case .easy: return "Lugn grupp"
        case .tempo: return "Tempogrupp"
        case .fast: return "Snabb grupp"
        case .race: return "Tävlingsfart"
        }
    }

    var wattsPerKg: Double {
        switch self {
        case .none: return 0
        case .easy: return 2.0
        case .tempo: return 2.7
        case .fast: return 3.4
        case .race: return 4.1
        }
    }

    var riderCount: Int { self == .none ? 0 : 6 }
}

enum CameraMode: String, Codable, CaseIterable, Identifiable {
    case chase, close, firstPerson, side, drone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chase: return "Bakom"
        case .close: return "Nära"
        case .firstPerson: return "Förstaperson"
        case .side: return "Från sidan"
        case .drone: return "Drönare"
        }
    }

    var next: CameraMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// JSON files in ~/Library/Application Support/Bikeinside.
/// Ride index (no samples) is kept separate from full ride files so the
/// history list loads instantly however many rides there are.
struct Storage {
    let root: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = base.appendingPathComponent("Bikeinside", isDirectory: true)
        try? FileManager.default.createDirectory(at: ridesDir, withIntermediateDirectories: true)
    }

    private var ridesDir: URL { root.appendingPathComponent("Rides", isDirectory: true) }

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? Self.decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? Self.encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    // MARK: Rides

    func loadRideIndex() -> [RideRecord] {
        (load([RideRecord].self, from: "rides-index.json") ?? []).sorted { $0.startDate > $1.startDate }
    }

    func saveRide(_ ride: RideRecord, index: [RideRecord]) {
        if let data = try? Self.encoder.encode(ride) {
            try? data.write(to: ridesDir.appendingPathComponent("\(ride.id.uuidString).json"), options: .atomic)
        }
        save(index, to: "rides-index.json")
    }

    func loadRide(id: UUID) -> RideRecord? {
        guard let data = try? Data(contentsOf: ridesDir.appendingPathComponent("\(id.uuidString).json")) else { return nil }
        return try? Self.decoder.decode(RideRecord.self, from: data)
    }

    func deleteRide(id: UUID, index: [RideRecord]) {
        try? FileManager.default.removeItem(at: ridesDir.appendingPathComponent("\(id.uuidString).json"))
        save(index, to: "rides-index.json")
    }
}
