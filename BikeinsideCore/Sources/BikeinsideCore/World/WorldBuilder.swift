import Foundation

/// Everything needed to render a route, generated off the main thread.
public struct WorldGeometry: Sendable {
    public var terrain: Terrain
    public var terrainChunks: [Terrain.Chunk]
    /// Trees, rocks and houses merged per chunk (same grid as terrain).
    public var sceneryChunks: [Terrain.Chunk]
    public var road: Mesh
    public var arches: Mesh
    public var stats: Stats

    public struct Stats: Sendable {
        public var trees = 0
        public var rocks = 0
        public var houses = 0
        public var triangles = 0
    }
}

public enum WorldBuilder {
    public static func build(route: Route, progress: (@Sendable (Double) -> Void)? = nil) -> WorldGeometry {
        progress?(0.05)
        let terrain = Terrain.generate(for: route)
        progress?(0.4)
        let chunks = terrain.meshChunks()
        progress?(0.55)
        var stats = WorldGeometry.Stats()
        let scenery = buildScenery(route: route, terrain: terrain, stats: &stats)
        progress?(0.85)
        let road = buildRoad(route: route)
        let arches = buildArches(route: route)
        stats.triangles = chunks.reduce(0) { $0 + $1.mesh.triangleCount }
            + scenery.reduce(0) { $0 + $1.mesh.triangleCount } + road.triangleCount + arches.triangleCount
        progress?(1)
        return WorldGeometry(terrain: terrain, terrainChunks: chunks, sceneryChunks: scenery, road: road, arches: arches, stats: stats)
    }

    // MARK: Road

    /// Asphalt ribbon with edge lines and a dashed centre line (3 m line, 9 m gap).
    public static func buildRoad(route: Route) -> Mesh {
        var m = Mesh()
        let n = route.points.count
        let half = Float(Terrain.roadHalfWidth)
        let asphalt = Float3(0.20, 0.20, 0.22)
        let shoulder = Float3(0.40, 0.38, 0.34)
        let paint = Float3(0.92, 0.92, 0.88)
        let lift: Float = 0.06
        m.reserve(vertices: n * 16, indices: n * 30)

        func frame(_ i: Int) -> (p: Float3, side: Float3) {
            let p = route.points[i]
            let h = route.headings[i]
            // Rider's right = forward × up = (-hz, 0, hx) in a Y-up right-handed world.
            let right = Float3(Float(-h.y), 0, Float(h.x))
            return (Float3(Float(p.x), Float(p.y) + lift, Float(p.z)), right)
        }

        // Strips are built as smooth ribbons (shared vertices along the road).
        func ribbon(from a: Float, to b: Float, dy: Float, color: Float3, dashed: Bool = false, dropOuter: Float = 0) {
            let stride = route.isLoop ? n : n - 1
            var base = UInt32(m.vertexCount)
            for i in 0..<n {
                let f = frame(i)
                let pa = f.p + f.side * a + Float3(0, dy - (a.magnitude > half ? dropOuter : 0), 0)
                let pb = f.p + f.side * b + Float3(0, dy - (b.magnitude > half ? dropOuter : 0), 0)
                m.addVertex(pa, normal: Float3(0, 1, 0), color: color)
                m.addVertex(pb, normal: Float3(0, 1, 0), color: color)
            }
            let dashPeriod = 12.0, dashLen = 3.0
            for i in 0..<stride {
                if dashed {
                    let d = Double(i) * route.spacing
                    if d.truncatingRemainder(dividingBy: dashPeriod) >= dashLen { continue }
                }
                let j = (i + 1) % n
                let a0 = base + UInt32(2 * i), b0 = a0 + 1
                let a1 = base + UInt32(2 * j), b1 = a1 + 1
                // ensure upward-facing winding regardless of which side a/b are on
                if a < b {
                    m.indices.append(contentsOf: [a0, b0, b1, a0, b1, a1])
                } else {
                    m.indices.append(contentsOf: [a0, a1, b1, a0, b1, b0])
                }
            }
            base = UInt32(m.vertexCount)
        }

        // gravel shoulders that dip into the terrain bed so no seams show
        ribbon(from: half, to: half + 1.6, dy: -0.02, color: shoulder, dropOuter: 0.5)
        ribbon(from: -half - 1.6, to: -half, dy: -0.02, color: shoulder, dropOuter: 0.5)
        ribbon(from: -half, to: half, dy: 0, color: asphalt)
        ribbon(from: half - 0.35, to: half - 0.2, dy: 0.012, color: paint)
        ribbon(from: -half + 0.2, to: -half + 0.35, dy: 0.012, color: paint)
        ribbon(from: -0.07, to: 0.07, dy: 0.012, color: paint, dashed: true)
        fixWinding(&m)
        return m
    }

    /// Makes every triangle face up (+Y). Cheap and robust regardless of travel direction.
    static func fixWinding(_ m: inout Mesh) {
        var k = 0
        while k + 2 < m.indices.count {
            let a = m.positions[Int(m.indices[k])], b = m.positions[Int(m.indices[k + 1])], c = m.positions[Int(m.indices[k + 2])]
            let u = b - a, v = c - a
            let ny = u.z * v.x - u.x * v.z
            if ny < 0 { m.indices.swapAt(k + 1, k + 2) }
            k += 3
        }
    }

    // MARK: Arches

    public static func buildArches(route: Route) -> Mesh {
        var m = Mesh()
        let half = Float(Terrain.roadHalfWidth + 2)
        func place(_ proto: Mesh, at distance: Double) {
            let s = route.sample(at: distance)
            // arch spans local X; align X with the road's lateral axis → yaw so local +Z = heading
            let yaw = Float(atan2(s.heading.x, s.heading.y))
            m.append(proto, transform: MeshTransform(
                translation: Float3(Float(s.position.x), Float(s.position.y), Float(s.position.z)), yaw: yaw))
        }
        place(Primitives.arch(halfWidth: half, color: Float3(0.1, 0.1, 0.1), checkered: true), at: 0)
        for seg in route.segments {
            let color = seg.kind == .climb ? Float3(0.90, 0.38, 0.08) : Float3(0.10, 0.62, 0.30)
            let proto = Primitives.arch(halfWidth: half, color: color, checkered: false)
            place(proto, at: seg.startDistance)
            place(proto, at: seg.endDistance)
        }
        return m
    }

    // MARK: Scenery

    static func buildScenery(route: Route, terrain: Terrain, stats: inout WorldGeometry.Stats) -> [Terrain.Chunk] {
        let chunkSize = 64.0 * terrain.cellSize
        let chunkCols = Int((terrain.width / chunkSize).rounded(.up))
        let chunkRows = Int((terrain.depth / chunkSize).rounded(.up))
        var meshes = [Mesh](repeating: Mesh(), count: chunkCols * chunkRows)
        func chunkIndex(_ x: Double, _ z: Double) -> Int {
            let c = min(max(Int((x - terrain.originX) / chunkSize), 0), chunkCols - 1)
            let r = min(max(Int((z - terrain.originZ) / chunkSize), 0), chunkRows - 1)
            return r * chunkCols + c
        }

        let protos: [(spruce: Mesh, pine: Mesh, birch: Mesh)] = [
            (Primitives.spruce(detail: true), Primitives.pine(detail: true), Primitives.birch(detail: true)),
            (Primitives.spruce(detail: false), Primitives.pine(detail: false), Primitives.birch(detail: false)),
        ]
        let rocks = (0..<4).map { Primitives.rock(seed: UInt64($0) &+ 11) }
        var rng = SeededRandom(seed: route.seed &+ 99)
        let style = terrain.style
        let water = terrain.waterLevel

        func usable(_ x: Double, _ z: Double, clearance: Double) -> (h: Double, n: Vec3)? {
            guard terrain.contains(x: x, z: z) else { return nil }
            if terrain.roadDistance(x: x, z: z) < clearance + terrain.cellSize { // cheap pre-check
                if terrain.roadDistance(x: x, z: z, route: route) < clearance { return nil }
            }
            let h = terrain.height(x: x, z: z)
            if let w = water, h < w + 1.2 { return nil }
            return (h, terrain.normal(x: x, z: z))
        }

        // Trees: dense jittered grid near the road, sparse further out.
        let bands: [(spacing: Double, minD: Double, maxD: Double, lod: Int)] = [
            (10.5, 9, 210, 0), (26, 210, 850, 1),
        ]
        for band in bands {
            var z = terrain.originZ
            while z < terrain.originZ + terrain.depth {
                var x = terrain.originX
                while x < terrain.originX + terrain.width {
                    let jx = x + rng.range(0, band.spacing), jz = z + rng.range(0, band.spacing)
                    let roll = rng.unit(), kindRoll = rng.unit(), scaleRoll = rng.unit(), yawRoll = rng.unit()
                    x += band.spacing
                    let dApprox = terrain.roadDistance(x: jx, z: jz)
                    guard dApprox >= band.minD - terrain.cellSize, dApprox < band.maxD else { continue }
                    let density = terrain.forestDensity(x: jx, z: jz)
                    // sparse lone trees in meadows, thick in forests
                    guard roll < 0.05 + density * 0.9 else { continue }
                    guard let spot = usable(jx, jz, clearance: max(band.minD, 9)) else { continue }
                    if spot.n.y < 0.8 { continue }
                    if let tl = style.treeLine, spot.h > tl + (density - 0.5) * 40 { continue }
                    let p = protos[band.lod]
                    let birchShare = 0.12 + (1 - density) * 0.45
                    let proto: Mesh
                    let tint: Float3
                    if kindRoll < birchShare {
                        proto = p.birch
                        tint = Float3(repeating: Float(0.9 + 0.2 * scaleRoll))
                    } else if kindRoll < birchShare + 0.3 {
                        proto = p.pine
                        tint = Float3(repeating: Float(0.92 + 0.16 * scaleRoll))
                    } else {
                        proto = p.spruce
                        tint = Float3(Float(0.9 + 0.15 * yawRoll), Float(0.92 + 0.16 * scaleRoll), 1)
                    }
                    let scale = Float(0.7 + 0.6 * scaleRoll)
                    meshes[chunkIndex(jx, jz)].append(proto, transform: MeshTransform(
                        translation: Float3(Float(jx), Float(spot.h) - 0.3, Float(jz)),
                        yaw: Float(yawRoll * 2 * .pi), uniformScale: scale), tint: tint)
                    stats.trees += 1
                }
                z += band.spacing
            }
        }

        // Rocks: more on mountains, a few boulders elsewhere.
        let rockCount = route.theme == .mountain ? 1400 : 350
        var placed = 0, attempts = 0
        while placed < rockCount && attempts < rockCount * 20 {
            attempts += 1
            let x = terrain.originX + rng.unit() * terrain.width
            let z = terrain.originZ + rng.unit() * terrain.depth
            let s = rng.range(0.6, 2.6), yaw = rng.range(0, 2 * .pi), pick = Int(rng.unit() * 4) % 4
            guard terrain.roadDistance(x: x, z: z) < 700, let spot = usable(x, z, clearance: 7) else { continue }
            meshes[chunkIndex(x, z)].append(rocks[pick], transform: MeshTransform(
                translation: Float3(Float(x), Float(spot.h) - Float(s) * 0.25, Float(z)),
                yaw: Float(yaw), scale: Float3(Float(s), Float(s * 0.8), Float(s))))
            placed += 1
        }
        stats.rocks = placed

        // Cottages: in clearings 18–60 m from the road, facing it, some with a flag.
        do {
            let cottage = Primitives.cottage()
            let flag = Primitives.flagpole()
            let target = Int(route.length / 450)
            var houses = 0
            var tries = 0
            while houses < target && tries < target * 60 {
                tries += 1
                let d = rng.unit() * route.length
                let side = rng.unit() < 0.5 ? -1.0 : 1.0
                let offset = rng.range(18, 60)
                let s = route.sample(at: d)
                let right = Vec2(-s.heading.y, s.heading.x)
                let pos = s.position.xz + right * (side * offset)
                guard terrain.forestDensity(x: pos.x, z: pos.y) < 0.45 else { continue }
                guard let spot = usable(pos.x, pos.y, clearance: 16), spot.n.y > 0.94 else { continue }
                if let tl = style.treeLine, spot.h > tl { continue }
                // face the road: local +Z (door side) points back towards the road
                let toRoad = (s.position.xz - pos).normalized
                let yaw = Float(atan2(toRoad.x, toRoad.y))
                let roof = rng.unit() < 0.5 ? Float3(0.18, 0.17, 0.17) : Float3(0.45, 0.20, 0.14)
                let ci = chunkIndex(pos.x, pos.y)
                meshes[ci].append(cottage, transform: MeshTransform(
                    translation: Float3(Float(pos.x), Float(spot.h), Float(pos.y)), yaw: yaw),
                    tint: Float3(1, 1, 1) * (roof.x > 0.3 ? 1 : 0.97))
                if rng.unit() < 0.5 {
                    let fp = pos + toRoad * 7 + Vec2(-toRoad.y, toRoad.x) * 4
                    let fh = terrain.height(x: fp.x, z: fp.y)
                    meshes[chunkIndex(fp.x, fp.y)].append(flag, transform: MeshTransform(
                        translation: Float3(Float(fp.x), Float(fh), Float(fp.y)), yaw: Float(rng.range(0, 2 * .pi))))
                }
                houses += 1
            }
            stats.houses = houses
        }

        var result: [Terrain.Chunk] = []
        for r in 0..<chunkRows {
            for c in 0..<chunkCols where !meshes[r * chunkCols + c].isEmpty {
                let center = Vec3(terrain.originX + (Double(c) + 0.5) * chunkSize, 0,
                                  terrain.originZ + (Double(r) + 0.5) * chunkSize)
                result.append(Terrain.Chunk(mesh: meshes[r * chunkCols + c], center: center))
            }
        }
        return result
    }
}
