import Foundation

/// The person on the bike. Persisted as JSON by the app.
public struct RiderProfile: Codable, Sendable, Equatable {
    public var name: String
    public var weightKg: Double
    public var heightCm: Double
    /// Functional threshold power in watts.
    public var ftp: Double
    public var maxHeartRate: Int?
    public var bikeWeightKg: Double
    /// Jersey colour as an index into `RiderProfile.jerseyPalette`.
    public var jerseyColorIndex: Int

    public init(
        name: String = "Cyklist",
        weightKg: Double = 75,
        heightCm: Double = 180,
        ftp: Double = 200,
        maxHeartRate: Int? = nil,
        bikeWeightKg: Double = 8.5,
        jerseyColorIndex: Int = 0
    ) {
        self.name = name
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.ftp = ftp
        self.maxHeartRate = maxHeartRate
        self.bikeWeightKg = bikeWeightKg
        self.jerseyColorIndex = jerseyColorIndex
    }

    public static let `default` = RiderProfile()

    /// Jersey colours (RGB 0...1) offered in the profile editor.
    public static let jerseyPalette: [SIMD3<Double>] = [
        SIMD3(0.05, 0.35, 0.75), // blå
        SIMD3(0.95, 0.78, 0.10), // gul
        SIMD3(0.80, 0.12, 0.15), // röd
        SIMD3(0.10, 0.55, 0.30), // grön
        SIMD3(0.95, 0.45, 0.10), // orange
        SIMD3(0.45, 0.20, 0.65), // lila
        SIMD3(0.12, 0.12, 0.14), // svart
        SIMD3(0.92, 0.92, 0.94), // vit
    ]

    public var wattsPerKgAtFTP: Double { ftp / max(weightKg, 1) }

    /// Frontal area in m² (Bassett et al. 1999), height in metres.
    public var frontalArea: Double {
        let h = heightCm / 100
        return 0.0293 * pow(h, 0.725) * pow(weightKg, 0.425) + 0.0604
    }

    /// Drag area for a rider on the hoods.
    public var cda: Double { frontalArea * 0.88 }

    /// Clamp values to something physically sensible (used after editing/decoding).
    public func sanitized() -> RiderProfile {
        var p = self
        p.weightKg = Interp.clamp(p.weightKg.isFinite ? p.weightKg : 75, 30, 200)
        p.heightCm = Interp.clamp(p.heightCm.isFinite ? p.heightCm : 180, 120, 230)
        p.ftp = Interp.clamp(p.ftp.isFinite ? p.ftp : 200, 50, 600)
        p.bikeWeightKg = Interp.clamp(p.bikeWeightKg.isFinite ? p.bikeWeightKg : 8.5, 4, 30)
        if let hr = p.maxHeartRate { p.maxHeartRate = min(max(hr, 100), 230) }
        p.jerseyColorIndex = min(max(p.jerseyColorIndex, 0), Self.jerseyPalette.count - 1)
        if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = "Cyklist" }
        return p
    }
}

/// Coggan-style power zones relative to FTP.
public enum PowerZone: Int, CaseIterable, Sendable {
    case z1 = 1, z2, z3, z4, z5, z6, z7

    public static func zone(power: Double, ftp: Double) -> PowerZone {
        guard ftp > 0 else { return .z1 }
        let r = power / ftp
        switch r {
        case ..<0.55: return .z1
        case ..<0.76: return .z2
        case ..<0.91: return .z3
        case ..<1.06: return .z4
        case ..<1.21: return .z5
        case ..<1.51: return .z6
        default: return .z7
        }
    }

    public var name: String {
        switch self {
        case .z1: return "Återhämtning"
        case .z2: return "Uthållighet"
        case .z3: return "Tempo"
        case .z4: return "Tröskel"
        case .z5: return "VO2max"
        case .z6: return "Anaerob"
        case .z7: return "Neuromuskulär"
        }
    }
}
