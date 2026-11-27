import Foundation

/// Distant scenery beyond the playable terrain: a ring of snow-capped
/// mountains (fjäll) or low forested ridges, so the horizon is never empty.
public enum Backdrop {
    public struct Ring: Sendable {
        public var radius: Double
        public var minHeight: Double
        public var maxHeight: Double
        public var lowColor: Float3
        public var highColor: Float3
        /// Height above base where snow starts (nil = no snow).
        public var snowAbove: Double?
        public var wavelength: Double
    }

    public static func rings(for route: Route, terrain: Terrain) -> [Ring] {
        let half = max(terrain.width, terrain.depth) / 2
        switch route.theme {
        case .mountain:
            return [
                Ring(radius: half + 900, minHeight: 250, maxHeight: 900, lowColor: Float3(0.36, 0.40, 0.36),
                     highColor: Float3(0.52, 0.53, 0.56), snowAbove: 520, wavelength: 5),
                Ring(radius: half + 2600, minHeight: 600, maxHeight: 1700, lowColor: Float3(0.40, 0.44, 0.52),
                     highColor: Float3(0.55, 0.58, 0.66), snowAbove: 900, wavelength: 7),
            ]
        case .forest:
            return [
                Ring(radius: half + 700, minHeight: 50, maxHeight: 190, lowColor: Float3(0.16, 0.28, 0.17),
                     highColor: Float3(0.20, 0.34, 0.22), snowAbove: nil, wavelength: 9),
                Ring(radius: half + 2200, minHeight: 120, maxHeight: 380, lowColor: Float3(0.24, 0.34, 0.34),
                     highColor: Float3(0.30, 0.40, 0.42), snowAbove: nil, wavelength: 6),
            ]
        case .coast:
            return [
                Ring(radius: half + 600, minHeight: 0, maxHeight: 70, lowColor: Float3(0.40, 0.40, 0.36),
                     highColor: Float3(0.22, 0.36, 0.22), snowAbove: nil, wavelength: 11),
                Ring(radius: half + 2400, minHeight: 0, maxHeight: 110, lowColor: Float3(0.32, 0.38, 0.40),
                     highColor: Float3(0.30, 0.40, 0.38), snowAbove: nil, wavelength: 9),
            ]
        case .lake:
            return [
                Ring(radius: half + 1500, minHeight: 40, maxHeight: 220, lowColor: Float3(0.18, 0.30, 0.20),
                     highColor: Float3(0.24, 0.36, 0.28), snowAbove: nil, wavelength: 8),
                Ring(radius: half + 3200, minHeight: 100, maxHeight: 420, lowColor: Float3(0.28, 0.36, 0.42),
                     highColor: Float3(0.34, 0.42, 0.50), snowAbove: nil, wavelength: 5),
            ]
        }
    }

    /// Builds all rings as one flat-shaded mesh whose faces point towards the centre.
    public static func build(route: Route, terrain: Terrain) -> Mesh {
        var m = Mesh()
        let cx = terrain.originX + terrain.width / 2
        let cz = terrain.originZ + terrain.depth / 2
        let base = route.theme == .coast ? (route.waterLevel ?? 0) - 25 : route.minElevation - 60
        let noise = ValueNoise2D(seed: route.seed &+ 404)
        for (ri, ring) in rings(for: route, terrain: terrain).enumerated() {
            let samples = 240
            // Height profile around the ring: smooth periodic noise, sharpened into peaks.
            func height(_ k: Int) -> Double {
                let a = Double(k % samples) / Double(samples) * 2 * .pi
                let n = noise.fbm(cos(a) * ring.wavelength + Double(ri) * 31, sin(a) * ring.wavelength, octaves: 5) * 0.5 + 0.5
                let peaky = pow(Interp.clamp(n, 0, 1), 1.6)
                return ring.minHeight + (ring.maxHeight - ring.minHeight) * peaky
            }
            let rows: [Double] = [0, 0.35, 0.62, 0.82, 1.0]
            var grid: [[Float3]] = []
            var heights: [Double] = []
            for k in 0...samples {
                let a = Double(k) / Double(samples) * 2 * .pi
                let h = height(k)
                heights.append(h)
                var col: [Float3] = []
                for (ti, t) in rows.enumerated() {
                    // slopes lean inwards; jitter breaks up the regular look
                    let jitter = noise.sample(Double(k) * 0.37, Double(ti) * 1.3 + Double(ri) * 7) * h * 0.08
                    let r = ring.radius - t * h * 1.1 + (ti == 0 ? 0 : jitter)
                    col.append(Float3(Float(cx + cos(a) * r), Float(base + t * h), Float(cz + sin(a) * r)))
                }
                grid.append(col)
            }
            let center = Float3(Float(cx), Float(base), Float(cz))
            for k in 0..<samples {
                for ti in 0..<(rows.count - 1) {
                    let a = grid[k][ti], b = grid[k + 1][ti], c = grid[k + 1][ti + 1], d = grid[k][ti + 1]
                    let topY = Double(max(c.y, d.y)) - base
                    var color = ring.lowColor + (ring.highColor - ring.lowColor) * Float(Double(ti) / Double(rows.count - 1))
                    if let snow = ring.snowAbove, topY > snow {
                        let s = Float(Interp.smoothstep(snow, snow + 120, topY))
                        color = color + (Float3(0.94, 0.95, 0.98) - color) * s
                    }
                    addFacing(&m, a, b, c, color: color, towards: center)
                    addFacing(&m, a, c, d, color: color, towards: center)
                }
            }
        }
        return m
    }

    static func addFacing(_ m: inout Mesh, _ a: Float3, _ b: Float3, _ c: Float3, color: Float3, towards p: Float3) {
        let n = Mesh.faceNormal(a, b, c)
        let centroid = (a + b + c) / 3
        if (n * (p - centroid)).sum() >= 0 {
            m.addTriangle(a, b, c, color: color)
        } else {
            m.addTriangle(a, c, b, color: color)
        }
    }
}
