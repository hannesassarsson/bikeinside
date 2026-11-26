import Foundation

public enum SceneryTheme: String, Codable, Sendable, CaseIterable {
    case forest, lake, mountain
}

public struct RouteSegment: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable { case climb, sprint }
    public let id: String
    public let name: String
    public let kind: Kind
    public let startDistance: Double
    public let endDistance: Double

    public var length: Double { endDistance - startDistance }
}

/// A position along a route.
public struct RouteSample: Sendable, Equatable {
    /// World position of the road centre (x, y = elevation, z).
    public var position: Vec3
    /// Unit direction of travel in the horizontal plane (x, z).
    public var heading: Vec2
    /// Rise / run.
    public var grade: Double
    public var elevation: Double { position.y }
    /// Distance wrapped into [0, length) for loops.
    public var distance: Double
}

/// A rideable road: uniformly resampled centre line with precomputed grade.
public struct Route: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let theme: SceneryTheme
    public let isLoop: Bool
    public let seed: UInt64
    /// Spacing between consecutive points along the road (metres).
    public let spacing: Double
    /// Centre-line points (x, elevation, z). For loops the closing segment
    /// runs from the last point back to the first.
    public let points: [Vec3]
    public let grades: [Double]
    public let headings: [Vec2]
    public let length: Double
    public let totalAscent: Double
    public let segments: [RouteSegment]
    /// Water surface height for scenery (nil = no lakes).
    public let waterLevel: Double?

    public init(
        id: String, name: String, summary: String, theme: SceneryTheme, isLoop: Bool, seed: UInt64,
        spacing: Double, points: [Vec3], grades: [Double], headings: [Vec2], length: Double,
        totalAscent: Double, segments: [RouteSegment], waterLevel: Double?
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.theme = theme
        self.isLoop = isLoop
        self.seed = seed
        self.spacing = spacing
        self.points = points
        self.grades = grades
        self.headings = headings
        self.length = length
        self.totalAscent = totalAscent
        self.segments = segments
        self.waterLevel = waterLevel
    }

    public var minElevation: Double { points.map(\.y).min() ?? 0 }
    public var maxElevation: Double { points.map(\.y).max() ?? 0 }
    public var maxGrade: Double { grades.max() ?? 0 }

    /// Wrap/clamp a distance onto the route.
    public func normalize(_ distance: Double) -> Double {
        if isLoop {
            var d = distance.truncatingRemainder(dividingBy: length)
            if d < 0 { d += length }
            return d
        }
        return Interp.clamp(distance, 0, length)
    }

    /// Interpolated state at any distance (wraps on loops).
    public func sample(at distance: Double) -> RouteSample {
        let d = normalize(distance)
        let n = points.count
        let f = d / spacing
        var i = Int(f.rounded(.down))
        var t = f - Double(i)
        if isLoop {
            i = ((i % n) + n) % n
        } else if i >= n - 1 {
            i = n - 2
            t = 1
        }
        let j = isLoop ? (i + 1) % n : i + 1
        let p = points[i] + (points[j] - points[i]) * t
        let g = Interp.mix(grades[i], grades[j], t)
        let h = (headings[i] + (headings[j] - headings[i]) * t).normalized
        return RouteSample(position: p, heading: h, grade: g, distance: d)
    }

    /// Elevation profile resampled to `count` values (for charts).
    public func elevationProfile(count: Int) -> [Double] {
        guard count > 1 else { return [points.first?.y ?? 0] }
        return (0..<count).map { k in
            sample(at: length * Double(k) / Double(count - 1) * (isLoop ? 0.99999 : 1)).elevation
        }
    }

    /// Climb-weighted average grade between two distances.
    public func averageGrade(from a: Double, to b: Double) -> Double {
        guard b > a else { return 0 }
        return (sample(at: b).elevation - sample(at: a).elevation) / (b - a)
    }

    public func segment(at distance: Double) -> RouteSegment? {
        let d = normalize(distance)
        return segments.first { d >= $0.startDistance && d < $0.endDistance }
    }
}
