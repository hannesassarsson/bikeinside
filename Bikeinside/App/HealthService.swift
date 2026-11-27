import BikeinsideCore
import Foundation

/// Reads recovery metrics from garmin-bridge via the token-protected
/// `bikeinside_readiness` RPC (returns only sleep/HRV/resting HR/readiness).
enum HealthService {
    enum HealthError: LocalizedError {
        case unauthorized
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Garmin-token godkändes inte"
            case .http(let c): return "Kunde inte hämta Garmin-data (\(c))"
            }
        }
    }

    static func fetch(token: String) async throws -> [HealthDay] {
        var req = URLRequest(url: URL(string: MultiplayerConfig.projectURL + "/rest/v1/rpc/bikeinside_readiness")!)
        req.httpMethod = "POST"
        req.setValue(MultiplayerConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["p_token": token])
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw HealthError.unauthorized }
        guard (200..<300).contains(code) else { throw HealthError.http(code) }
        return try JSONDecoder().decode([HealthDay].self, from: data)
    }
}

extension Data {
    /// Stable hex digest (FNV-1a) used for ids of imported files.
    var hashValueStableHex: String {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in self { h = (h ^ UInt64(b)) &* 0x100_0000_01B3 }
        return String(h, radix: 16)
    }
}
