import Foundation

/// Hand-authored description of a route: a closed horizontal shape plus an
/// elevation profile. `RouteBuilder` turns it into a smooth, evenly spaced road.
public struct RouteBlueprint: Sendable {
    public struct ElevationKey: Sendable {
        /// Position along the loop, 0 ..< 1.
        public var t: Double
        public var elevation: Double
        public init(_ t: Double, _ elevation: Double) {
            self.t = t
            self.elevation = elevation
        }
    }

    public struct SprintSpec: Sendable {
        public var name: String
        public var startFraction: Double
        public var lengthMeters: Double
        public init(name: String, startFraction: Double, lengthMeters: Double) {
            self.name = name
            self.startFraction = startFraction
            self.lengthMeters = lengthMeters
        }
    }

    public var id: String
    public var name: String
    public var summary: String
    public var theme: SceneryTheme
    public var seed: UInt64
    /// Closed loop of horizontal control points (x, z) in metres.
    public var controlPoints: [Vec2]
    public var elevation: [ElevationKey]
    /// Names given to automatically detected climbs, in route order.
    public var climbNames: [String]
    public var sprints: [SprintSpec]
    public var waterLevel: Double?
    public var surface: RoadSurface

    public init(
        id: String, name: String, summary: String, theme: SceneryTheme, seed: UInt64,
        controlPoints: [Vec2], elevation: [ElevationKey], climbNames: [String] = [],
        sprints: [SprintSpec] = [], waterLevel: Double? = nil, surface: RoadSurface = .asphalt
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.theme = theme
        self.seed = seed
        self.controlPoints = controlPoints
        self.elevation = elevation
        self.climbNames = climbNames
        self.sprints = sprints
        self.waterLevel = waterLevel
        self.surface = surface
    }
}

public enum RouteBuilder {
    public static func build(_ bp: RouteBlueprint, spacing targetSpacing: Double = 2.0) -> Route {
        precondition(bp.controlPoints.count >= 4, "need at least 4 control points")
        precondition(!bp.elevation.isEmpty, "need elevation keys")

        // 1. Dense centripetal Catmull-Rom through the closed control polygon.
        let dense = closedCatmullRom(bp.controlPoints, samplesPerSegment: 64)

        // 2. Arc-length table.
        var cum = [0.0]
        cum.reserveCapacity(dense.count + 1)
        for i in 0..<dense.count {
            let a = dense[i], b = dense[(i + 1) % dense.count]
            cum.append(cum[i] + (b - a).length)
        }
        let total = cum[dense.count]

        // 3. Uniform resample.
        let n = max(16, Int((total / targetSpacing).rounded()))
        let spacing = total / Double(n)
        var xz = [Vec2]()
        xz.reserveCapacity(n)
        var seg = 0
        for k in 0..<n {
            let s = Double(k) * spacing
            while seg < dense.count - 1 && cum[seg + 1] < s { seg += 1 }
            let segLen = cum[seg + 1] - cum[seg]
            let t = segLen > 0 ? (s - cum[seg]) / segLen : 0
            let a = dense[seg], b = dense[(seg + 1) % dense.count]
            xz.append(a + (b - a) * t)
        }

        // 4. Elevation: periodic monotone cubic over the keys, then smoothed.
        let keys = bp.elevation.sorted { $0.t < $1.t }
        var elev = (0..<n).map { periodicMonotoneCubic(keys, t: Double($0) / Double(n)) }
        elev = circularMovingAverage(elev, radius: max(1, Int((24 / spacing).rounded())))
        if let w = bp.waterLevel {
            elev = elev.map { max($0, w + 2.0) }
        }

        // 5. Grades, headings, ascent.
        let gr = max(1, Int((10 / spacing).rounded()))
        var grades = [Double](repeating: 0, count: n)
        var headings = [Vec2](repeating: Vec2(1, 0), count: n)
        var ascent = 0.0
        for i in 0..<n {
            let ip = (i + gr) % n, im = (i - gr + n) % n
            grades[i] = (elev[ip] - elev[im]) / (Double(2 * gr) * spacing)
            let h = xz[(i + 1) % n] - xz[(i - 1 + n) % n]
            headings[i] = h.normalized
            let dz = elev[(i + 1) % n] - elev[i]
            if dz > 0 { ascent += dz }
        }

        let points = (0..<n).map { Vec3(xz[$0].x, elev[$0], xz[$0].y) }

        // 6. Segments: auto-detected climbs + authored sprints.
        var segments: [RouteSegment] = []
        let climbs = detectClimbs(elevation: elev, spacing: spacing)
        for (idx, c) in climbs.enumerated() {
            let name = idx < bp.climbNames.count ? bp.climbNames[idx] : "Klättring \(idx + 1)"
            segments.append(RouteSegment(
                id: "\(bp.id)-climb-\(idx)", name: name, kind: .climb,
                startDistance: c.start, endDistance: c.end))
        }
        for (idx, s) in bp.sprints.enumerated() {
            let start = s.startFraction * total
            segments.append(RouteSegment(
                id: "\(bp.id)-sprint-\(idx)", name: s.name, kind: .sprint,
                startDistance: start, endDistance: min(start + s.lengthMeters, total - 1)))
        }
        segments.sort { $0.startDistance < $1.startDistance }

        return Route(
            id: bp.id, name: bp.name, summary: bp.summary, theme: bp.theme, isLoop: true,
            seed: bp.seed, spacing: spacing, points: points, grades: grades, headings: headings,
            length: total, totalAscent: ascent, segments: segments, waterLevel: bp.waterLevel, surface: bp.surface)
    }

    // MARK: - Curves

    /// Centripetal Catmull-Rom (alpha = 0.5): no cusps or self-intersections
    /// within a segment, even for unevenly spaced control points.
    static func closedCatmullRom(_ pts: [Vec2], samplesPerSegment: Int) -> [Vec2] {
        let n = pts.count
        var out: [Vec2] = []
        out.reserveCapacity(n * samplesPerSegment)
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            func knot(_ ti: Double, _ a: Vec2, _ b: Vec2) -> Double {
                ti + max((b - a).length.squareRoot(), 1e-6)
            }
            let t0 = 0.0
            let t1 = knot(t0, p0, p1)
            let t2 = knot(t1, p1, p2)
            let t3 = knot(t2, p2, p3)
            for s in 0..<samplesPerSegment {
                let t = t1 + (t2 - t1) * Double(s) / Double(samplesPerSegment)
                let a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
                let a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
                let a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
                let b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
                let b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
                out.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
            }
        }
        return out
    }

    /// Fritsch–Carlson monotone cubic over periodic keys: never overshoots,
    /// so authored peaks/valleys are exactly the extremes of the profile.
    static func periodicMonotoneCubic(_ keys: [RouteBlueprint.ElevationKey], t rawT: Double) -> Double {
        let n = keys.count
        if n == 1 { return keys[0].elevation }
        var t = rawT.truncatingRemainder(dividingBy: 1)
        if t < 0 { t += 1 }
        // Extended arrays with wrap-around neighbours.
        func key(_ i: Int) -> (t: Double, e: Double) {
            let wraps = Int((Double(i) / Double(n)).rounded(.down))
            let k = keys[((i % n) + n) % n]
            return (k.t + Double(wraps), k.elevation)
        }
        // Find interval i such that key(i).t <= t < key(i+1).t
        var i = -1
        while key(i + 1).t <= t { i += 1 }
        while key(i).t > t { i -= 1 }
        func secant(_ j: Int) -> Double {
            let a = key(j), b = key(j + 1)
            return (b.e - a.e) / max(b.t - a.t, 1e-9)
        }
        func tangent(_ j: Int) -> Double {
            let s0 = secant(j - 1), s1 = secant(j)
            if s0 * s1 <= 0 { return 0 }
            // harmonic mean keeps monotonicity
            return 2 / (1 / s0 + 1 / s1)
        }
        let a = key(i), b = key(i + 1)
        let h = b.t - a.t
        let u = (t - a.t) / h
        let m0 = tangent(i) * h, m1 = tangent(i + 1) * h
        let u2 = u * u, u3 = u2 * u
        return (2 * u3 - 3 * u2 + 1) * a.e + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * b.e + (u3 - u2) * m1
    }

    static func circularMovingAverage(_ v: [Double], radius: Int) -> [Double] {
        let n = v.count
        guard n > 0, radius > 0 else { return v }
        var out = [Double](repeating: 0, count: n)
        var sum = 0.0
        for k in -radius...radius { sum += v[((k % n) + n) % n] }
        let w = Double(2 * radius + 1)
        for i in 0..<n {
            out[i] = sum / w
            sum -= v[((i - radius) % n + n) % n]
            sum += v[(i + radius + 1) % n]
        }
        return out
    }

    /// Finds sustained climbs: ≥ 25 m gain at ≥ 2.5 % average, using hysteresis
    /// so small dips don't split a climb.
    static func detectClimbs(elevation e: [Double], spacing: Double) -> [(start: Double, end: Double)] {
        let n = e.count
        guard n > 2 else { return [] }
        // Start at the global minimum so a loop's climb never straddles index 0.
        let startIdx = e.indices.min { e[$0] < e[$1] }!
        let hysteresis = 6.0
        var result: [(Double, Double)] = []
        var lowIdx = startIdx, highIdx = startIdx
        var climbing = false
        for step in 1...n {
            let i = (startIdx + step) % n
            if climbing {
                if e[i] > e[highIdx] { highIdx = i }
                if e[highIdx] - e[i] > hysteresis || step == n {
                    // climb ended at highIdx
                    // Trim flat run-in / run-out so the segment starts where the road tilts up.
                    var s = lowIdx, f = highIdx
                    while (f - s + n) % n > 1, e[(s + 1) % n] - e[lowIdx] < 2.5 { s = (s + 1) % n }
                    while (f - s + n) % n > 1, e[highIdx] - e[(f - 1 + n) % n] < 2.5 { f = (f - 1 + n) % n }
                    let gain = e[f] - e[s]
                    let len = Double((f - s + n) % n) * spacing
                    if gain >= 18, len > 0, gain / len >= 0.02 {
                        result.append((Double(s) * spacing, Double(s) * spacing + len))
                    }
                    climbing = false
                    lowIdx = i
                }
            } else {
                if e[i] < e[lowIdx] { lowIdx = i }
                if e[i] - e[lowIdx] > hysteresis {
                    climbing = true
                    highIdx = i
                }
            }
        }
        // Distances for climbs past index 0 wrap; normalise into [0, total).
        let total = Double(n) * spacing
        return result
            .map { s, e2 in
                let s2 = s.truncatingRemainder(dividingBy: total)
                return (s2, s2 + (e2 - s))
            }
            .filter { $0.1 <= total } // climbs crossing the start/finish line are dropped
            .sorted { $0.0 < $1.0 }
    }
}
