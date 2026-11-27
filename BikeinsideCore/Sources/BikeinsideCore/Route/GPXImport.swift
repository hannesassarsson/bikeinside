import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A route imported from a GPX file (stored so it can be rebuilt any time).
public struct ImportedRoute: Codable, Equatable, Sendable, Identifiable {
    public struct Point: Codable, Equatable, Sendable {
        public var lat: Double
        public var lon: Double
        public var ele: Double?
    }

    public var id: String
    public var name: String
    public var theme: SceneryTheme
    public var points: [Point]
    public var importedAt: Date

    public init(id: String, name: String, theme: SceneryTheme, points: [Point], importedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.theme = theme
        self.points = points
        self.importedAt = importedAt
    }
}

public enum GPXImport {
    public enum ImportError: Error, Equatable {
        case noPoints
        case tooShort
        case tooLong(km: Int)
    }

    public static let maxLength = 80_000.0

    /// Parses track points (<trkpt>, falling back to <rtept>) with optional <ele>.
    public static func parse(_ data: Data, fallbackName: String) throws -> (name: String, points: [ImportedRoute.Point]) {
        let delegate = Parser()
        let p = XMLParser(data: data)
        p.delegate = delegate
        p.parse()
        let pts = delegate.track.isEmpty ? delegate.route : delegate.track
        guard pts.count >= 2 else { throw ImportError.noPoints }
        let name = delegate.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ((name?.isEmpty ?? true) ? fallbackName : name!, pts)
    }

    final class Parser: NSObject, XMLParserDelegate {
        var track: [ImportedRoute.Point] = []
        var route: [ImportedRoute.Point] = []
        var name: String?
        private var current: ImportedRoute.Point?
        private var currentIsTrack = true
        private var text = ""
        private var inEle = false
        private var depthName = 0

        func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let e = el.lowercased()
            if e == "trkpt" || e == "rtept" {
                if let la = attributes["lat"].flatMap(Double.init), let lo = attributes["lon"].flatMap(Double.init),
                   (-90...90).contains(la), (-180...180).contains(lo) {
                    current = ImportedRoute.Point(lat: la, lon: lo, ele: nil)
                    currentIsTrack = e == "trkpt"
                }
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
            let e = el.lowercased()
            switch e {
            case "ele":
                if current != nil, let v = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite { current?.ele = v }
            case "name":
                if name == nil && current == nil { name = text }
            case "trkpt", "rtept":
                if let c = current { if currentIsTrack { track.append(c) } else { route.append(c) } }
                current = nil
            default: break
            }
            text = ""
        }
    }

    /// Projects lat/lon to local metres (x east, z south, origin at the centroid).
    public static func project(_ pts: [ImportedRoute.Point]) -> [Vec3] {
        let lat0 = pts.map(\.lat).reduce(0, +) / Double(pts.count)
        let lon0 = pts.map(\.lon).reduce(0, +) / Double(pts.count)
        let r = 6_371_000.0
        let kx = cos(lat0 * .pi / 180) * r * .pi / 180
        let kz = r * .pi / 180
        let fallback = pts.compactMap(\.ele).first ?? 50
        return pts.map { p in
            Vec3((p.lon - lon0) * kx, p.ele ?? fallback, -(p.lat - lat0) * kz)
        }
    }

    /// Builds a rideable Route from an imported GPX track.
    public static func buildRoute(_ imp: ImportedRoute, spacing: Double = 2) throws -> Route {
        var raw = project(imp.points)
        // drop duplicate/near-duplicate points (GPS jitter at stops)
        var cleaned: [Vec3] = []
        for p in raw where cleaned.last.map({ ($0.xz - p.xz).length > 1.5 }) ?? true { cleaned.append(p) }
        raw = cleaned
        guard raw.count >= 2 else { throw ImportError.tooShort }
        var lengthTotal = 0.0
        for i in 1..<raw.count { lengthTotal += (raw[i].xz - raw[i - 1].xz).length }
        guard lengthTotal >= 500 else { throw ImportError.tooShort }
        guard lengthTotal <= maxLength else { throw ImportError.tooLong(km: Int(lengthTotal / 1000)) }
        let isLoop = (raw.first!.xz - raw.last!.xz).length < 150
        return RouteBuilder.buildOpenOrLoop(
            id: imp.id, name: imp.name, theme: imp.theme, seed: UInt64(truncatingIfNeeded: imp.id.hashValueStable),
            polyline: raw, isLoop: isLoop, spacing: spacing)
    }
}

extension String {
    /// FNV-1a hash that is stable across launches (unlike `hashValue`).
    public var hashValueStable: UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01B3 }
        return h
    }
}

extension RouteBuilder {
    /// Builds a route from a measured polyline (e.g. GPX): resamples evenly,
    /// smooths GPS noise out of the elevation and clamps unrealistic grades.
    public static func buildOpenOrLoop(
        id: String, name: String, theme: SceneryTheme, seed: UInt64, polyline raw: [Vec3], isLoop: Bool, spacing target: Double = 2
    ) -> Route {
        // light smoothing of the horizontal shape to remove GPS zig-zag
        var pts = raw
        if pts.count > 4 {
            for _ in 0..<2 {
                var s = pts
                for i in 1..<(pts.count - 1) {
                    let a = pts[i - 1].xz, b = pts[i].xz, c = pts[i + 1].xz
                    let m = (a + b * 2 + c) / 4
                    s[i] = Vec3(m.x, pts[i].y, m.y)
                }
                pts = s
            }
        }
        var poly = pts
        if isLoop { poly.append(pts[0]) }
        var cum = [0.0]
        for i in 1..<poly.count { cum.append(cum[i - 1] + (poly[i].xz - poly[i - 1].xz).length) }
        let total = cum.last!
        let n = max(16, Int((total / target).rounded()))
        let spacing = total / Double(n)
        let count = isLoop ? n : n + 1
        var xz: [Vec2] = []
        var elev: [Double] = []
        var seg = 0
        for k in 0..<count {
            let s = min(Double(k) * spacing, total)
            while seg < poly.count - 2 && cum[seg + 1] < s { seg += 1 }
            let len = cum[seg + 1] - cum[seg]
            let t = len > 0 ? (s - cum[seg]) / len : 0
            let p = poly[seg] + (poly[seg + 1] - poly[seg]) * t
            xz.append(p.xz)
            elev.append(p.y)
        }
        // elevation: ±60 m moving average (barometric/GPS noise), then clamp grade to ±18 %
        let r = max(1, Int((60 / spacing).rounded()))
        elev = isLoop ? circularMovingAverage(elev, radius: r) : linearMovingAverage(elev, radius: r)
        let maxStep = 0.18 * spacing
        for i in 1..<elev.count { elev[i] = Interp.clamp(elev[i], elev[i - 1] - maxStep, elev[i - 1] + maxStep) }

        let m = xz.count
        func idx(_ i: Int) -> Int { isLoop ? ((i % m) + m) % m : min(max(i, 0), m - 1) }
        let gr = max(1, Int((10 / spacing).rounded()))
        var grades = [Double](repeating: 0, count: m)
        var headings = [Vec2](repeating: Vec2(1, 0), count: m)
        var ascent = 0.0
        for i in 0..<m {
            let ip = idx(i + gr), im = idx(i - gr)
            let run = Double(isLoop ? 2 * gr : (ip - im)) * spacing
            grades[i] = run > 0 ? (elev[ip] - elev[im]) / run : 0
            let h = xz[idx(i + 1)] - xz[idx(i - 1)]
            headings[i] = h.length > 0 ? h.normalized : (i > 0 ? headings[i - 1] : Vec2(1, 0))
            if i + 1 < m || isLoop {
                let dz = elev[idx(i + 1)] - elev[i]
                if dz > 0 { ascent += dz }
            }
        }
        let points = (0..<m).map { Vec3(xz[$0].x, elev[$0], xz[$0].y) }
        var segments: [RouteSegment] = []
        for (k, c) in detectClimbs(elevation: elev, spacing: spacing, isLoop: isLoop).enumerated() {
            segments.append(RouteSegment(id: "\(id)-climb-\(k)", name: "Backe \(k + 1)", kind: .climb,
                                         startDistance: c.start, endDistance: c.end))
        }
        let length = isLoop ? Double(m) * spacing : Double(m - 1) * spacing
        return Route(id: id, name: name, summary: "Importerad GPX-rutt", theme: theme, isLoop: isLoop, seed: seed,
                     spacing: spacing, points: points, grades: grades, headings: headings, length: length,
                     totalAscent: ascent, segments: segments, waterLevel: nil)
    }

    static func linearMovingAverage(_ v: [Double], radius: Int) -> [Double] {
        guard !v.isEmpty else { return v }
        var prefix = [0.0]
        for x in v { prefix.append(prefix.last! + x) }
        return v.indices.map { i in
            let lo = max(0, i - radius), hi = min(v.count - 1, i + radius)
            return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
    }

    static func detectClimbs(elevation e: [Double], spacing: Double, isLoop: Bool) -> [(start: Double, end: Double)] {
        if isLoop { return detectClimbs(elevation: e, spacing: spacing) }
        // open route: simple scan with hysteresis
        var result: [(Double, Double)] = []
        var low = 0, high = 0, climbing = false
        for i in 1..<e.count {
            if climbing {
                if e[i] > e[high] { high = i }
                if e[high] - e[i] > 6 || i == e.count - 1 {
                    let gain = e[high] - e[low], len = Double(high - low) * spacing
                    if gain >= 18, len > 0, gain / len >= 0.02 { result.append((Double(low) * spacing, Double(high) * spacing)) }
                    climbing = false
                    low = i
                }
            } else {
                if e[i] < e[low] { low = i }
                if e[i] - e[low] > 6 { climbing = true; high = i }
            }
        }
        return result
    }
}
