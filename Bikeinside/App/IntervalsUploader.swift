import BikeinsideCore
import Foundation
import Security

/// Stores the intervals.icu API key in the macOS Keychain (never in files).
enum IntervalsKeychain {
    static func load() -> String? { TokenKeychain.load(service: "se.bikeinside.intervals") }
    static func save(_ key: String?) { TokenKeychain.save(key, service: "se.bikeinside.intervals") }
}

/// Generic secret storage in the macOS Keychain.
enum TokenKeychain {
    private static let account = "api-key"

    static func load(service: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func save(_ key: String?, service: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Uploads FIT files to intervals.icu (free), which can forward to Garmin
/// Connect, TrainingPeaks and others.
enum IntervalsUploader {
    enum UploadError: LocalizedError {
        case noKey
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noKey: return "Ingen API-nyckel för intervals.icu"
            case .http(let code, let body): return code == 401 || code == 403
                ? "intervals.icu nekade nyckeln (kontrollera API-nyckeln)"
                : "intervals.icu svarade \(code): \(body.prefix(120))"
            }
        }
    }

    /// Athlete "0" means the athlete that owns the API key.
    static func upload(_ ride: RideRecord, key: String) async throws {
        let name = (ride.workoutName.map { "\($0) – " } ?? "") + ride.routeName + " (Bikeinside)"
        var comps = URLComponents(string: "https://intervals.icu/api/v1/athlete/0/activities")!
        comps.queryItems = [URLQueryItem(name: "name", value: name)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        let auth = Data("API_KEY:\(key)".utf8).base64EncodedString()
        req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        let boundary = "bikeinside-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"bikeinside-\(ride.id.uuidString.prefix(8)).fit\"\r\n".utf8))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(FITEncoder.encode(ride))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw UploadError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
