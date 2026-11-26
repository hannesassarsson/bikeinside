import Foundation

/// Per-theme landscape knobs.
public struct TerrainStyle: Sendable {
    public var hillAmplitude: Double
    public var hillWavelength: Double
    /// Large distant mountains (0 = none).
    public var mountainAmplitude: Double
    public var forestCoverage: Double
    public var treeLine: Double?
    public var snowLine: Double?
    /// Carve a lake inside the loop.
    public var lakeInsideLoop: Bool

    public static func forTheme(_ theme: SceneryTheme) -> TerrainStyle {
        switch theme {
        case .forest:
            return TerrainStyle(hillAmplitude: 28, hillWavelength: 650, mountainAmplitude: 60, forestCoverage: 0.72,
                                treeLine: nil, snowLine: nil, lakeInsideLoop: false)
        case .lake:
            return TerrainStyle(hillAmplitude: 16, hillWavelength: 700, mountainAmplitude: 40, forestCoverage: 0.55,
                                treeLine: nil, snowLine: nil, lakeInsideLoop: true)
        case .mountain:
            return TerrainStyle(hillAmplitude: 45, hillWavelength: 800, mountainAmplitude: 520, forestCoverage: 0.6,
                                treeLine: 560, snowLine: 790, lakeInsideLoop: false)
        }
    }
}

/// Height field around a route, generated so that the road sits in a natural
/// cut/embankment and the landscape rises into hills further away.
public struct Terrain: Sendable {
    public let originX: Double
    public let originZ: Double
    public let cellSize: Double
    /// Node counts along x and z.
    public let cols: Int
    public let rows: Int
    public let heights: [Float]
    /// Horizontal distance from each node to the road centre line.
    public let roadDistance: [Float]
    /// Index into `route.points` of the closest centre-line point.
    public let nearestRoutePoint: [Int32]
    /// True for nodes enclosed by the loop.
    public let insideLoop: [Bool]
    public let waterLevel: Double?
    public let style: TerrainStyle
    public let seed: UInt64

    public static let roadHalfWidth = 3.5

    public var width: Double { Double(cols - 1) * cellSize }
    public var depth: Double { Double(rows - 1) * cellSize }

    @inlinable public func index(_ c: Int, _ r: Int) -> Int { r * cols + c }

    public func nodePosition(_ c: Int, _ r: Int) -> Vec3 {
        Vec3(originX + Double(c) * cellSize, Double(heights[index(c, r)]), originZ + Double(r) * cellSize)
    }

    /// Bilinear height at any world (x, z); clamps outside the grid.
    public func height(x: Double, z: Double) -> Double {
        let fx = Interp.clamp((x - originX) / cellSize, 0, Double(cols - 1) - 1e-9)
        let fz = Interp.clamp((z - originZ) / cellSize, 0, Double(rows - 1) - 1e-9)
        let c = Int(fx), r = Int(fz)
        let tx = fx - Double(c), tz = fz - Double(r)
        let h00 = Double(heights[index(c, r)]), h10 = Double(heights[index(c + 1, r)])
        let h01 = Double(heights[index(c, r + 1)]), h11 = Double(heights[index(c + 1, r + 1)])
        // match the triangle split used by the mesh (diagonal 00-11)
        if tx >= tz {
            return h00 + (h10 - h00) * tx + (h11 - h10) * tz
        } else {
            return h00 + (h11 - h01) * tx + (h01 - h00) * tz
        }
    }

    /// Unit surface normal from central differences.
    public func normal(x: Double, z: Double) -> Vec3 {
        let e = cellSize
        let dx = height(x: x + e, z: z) - height(x: x - e, z: z)
        let dz = height(x: x, z: z + e) - height(x: x, z: z - e)
        return Vec3(-dx, 2 * e, -dz).normalized
    }

    public func roadDistance(x: Double, z: Double) -> Double {
        let c = Int(Interp.clamp(((x - originX) / cellSize).rounded(), 0, Double(cols - 1)))
        let r = Int(Interp.clamp(((z - originZ) / cellSize).rounded(), 0, Double(rows - 1)))
        // Accurate to about half a cell: value stored at the nearest node.
        return Double(roadDistance[index(c, r)])
    }

    /// Exact distance to the road centre line, refining the node's nearest
    /// route point by searching its neighbours along the route.
    public func roadDistance(x: Double, z: Double, route: Route) -> Double {
        let c = Int(Interp.clamp(((x - originX) / cellSize).rounded(), 0, Double(cols - 1)))
        let r = Int(Interp.clamp(((z - originZ) / cellSize).rounded(), 0, Double(rows - 1)))
        let seed = Int(nearestRoutePoint[index(c, r)])
        let n = route.points.count
        let window = Int((cellSize * 2 / route.spacing).rounded(.up)) + 2
        var best = Double.infinity
        for k in -window...window {
            let i = route.isLoop ? ((seed + k) % n + n) % n : min(max(seed + k, 0), n - 1)
            best = min(best, (route.points[i].xz - Vec2(x, z)).length)
        }
        return best
    }

    public func isInsideLoop(x: Double, z: Double) -> Bool {
        let c = Int(Interp.clamp(((x - originX) / cellSize).rounded(), 0, Double(cols - 1)))
        let r = Int(Interp.clamp(((z - originZ) / cellSize).rounded(), 0, Double(rows - 1)))
        return insideLoop[index(c, r)]
    }

    public func contains(x: Double, z: Double) -> Bool {
        x >= originX && x <= originX + width && z >= originZ && z <= originZ + depth
    }

    /// Forest density 0...1 at a point (shared by colouring and tree placement).
    public func forestDensity(x: Double, z: Double) -> Double {
        let n = ValueNoise2D(seed: seed &+ 77).fbm(x / 420, z / 420, octaves: 3)
        let threshold = 0.5 - style.forestCoverage // coverage 0.7 → threshold -0.2
        return Interp.smoothstep(threshold - 0.12, threshold + 0.22, n)
    }

    // MARK: - Generation

    public static func generate(for route: Route, cellSize: Double = 8, margin: Double = 750) -> Terrain {
        let style = TerrainStyle.forTheme(route.theme)
        var minX = Double.infinity, maxX = -Double.infinity, minZ = Double.infinity, maxZ = -Double.infinity
        for p in route.points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        let ox = (minX - margin).rounded(.down), oz = (minZ - margin).rounded(.down)
        let cols = Int(((maxX + margin - ox) / cellSize).rounded(.up)) + 1
        let rows = Int(((maxZ + margin - oz) / cellSize).rounded(.up)) + 1
        let count = cols * rows

        // 1. Nearest route point per node via seeded distance propagation.
        var nearest = [Int32](repeating: -1, count: count)
        var dist = [Double](repeating: .infinity, count: count)
        let px = route.points.map(\.x), pz = route.points.map(\.z)

        @inline(__always) func d2(_ node: Int, _ p: Int32) -> Double {
            let c = node % cols, r = node / cols
            let dx = ox + Double(c) * cellSize - px[Int(p)]
            let dz = oz + Double(r) * cellSize - pz[Int(p)]
            return dx * dx + dz * dz
        }

        for (i, p) in route.points.enumerated() {
            let cc = Int(((p.x - ox) / cellSize).rounded()), rr = Int(((p.z - oz) / cellSize).rounded())
            for r in max(0, rr - 1)...min(rows - 1, rr + 1) {
                for c in max(0, cc - 1)...min(cols - 1, cc + 1) {
                    let node = r * cols + c
                    let dd = d2(node, Int32(i))
                    if dd < dist[node] {
                        dist[node] = dd
                        nearest[node] = Int32(i)
                    }
                }
            }
        }
        // Two forward/backward sweeps with 8-neighbourhood ("nearest seed" chamfer).
        let fwd = [(-1, -1), (0, -1), (1, -1), (-1, 0)]
        let bwd = [(1, 1), (0, 1), (-1, 1), (1, 0)]
        for _ in 0..<2 {
            for r in 0..<rows {
                for c in 0..<cols {
                    let node = r * cols + c
                    for (dc, dr) in fwd {
                        let nc = c + dc, nr = r + dr
                        guard nc >= 0, nc < cols, nr >= 0 else { continue }
                        let cand = nearest[nr * cols + nc]
                        if cand >= 0 {
                            let dd = d2(node, cand)
                            if dd < dist[node] { dist[node] = dd; nearest[node] = cand }
                        }
                    }
                }
            }
            for r in stride(from: rows - 1, through: 0, by: -1) {
                for c in stride(from: cols - 1, through: 0, by: -1) {
                    let node = r * cols + c
                    for (dc, dr) in bwd {
                        let nc = c + dc, nr = r + dr
                        guard nc >= 0, nc < cols, nr < rows else { continue }
                        let cand = nearest[nr * cols + nc]
                        if cand >= 0 {
                            let dd = d2(node, cand)
                            if dd < dist[node] { dist[node] = dd; nearest[node] = cand }
                        }
                    }
                }
            }
        }
        let roadDist = dist.map { Float($0.squareRoot()) }

        // 2. Inside-the-loop mask: 4-connected flood fill from the border that
        //    cannot cross the road (nodes within 0.75 cells of the centre line).
        var outside = [Bool](repeating: false, count: count)
        let barrier = Float(cellSize * 0.75)
        var stack: [Int] = []
        stack.reserveCapacity(4 * (cols + rows))
        for c in 0..<cols { stack.append(c); stack.append((rows - 1) * cols + c) }
        for r in 0..<rows { stack.append(r * cols); stack.append(r * cols + cols - 1) }
        while let node = stack.popLast() {
            if outside[node] || roadDist[node] <= barrier { continue }
            outside[node] = true
            let c = node % cols, r = node / cols
            if c > 0 { stack.append(node - 1) }
            if c < cols - 1 { stack.append(node + 1) }
            if r > 0 { stack.append(node - cols) }
            if r < rows - 1 { stack.append(node + cols) }
        }
        let inside = (0..<count).map { !outside[$0] && roadDist[$0] > barrier }

        // 3. Heights.
        let hills = ValueNoise2D(seed: route.seed &+ 1)
        let peaks = ValueNoise2D(seed: route.seed &+ 2)
        let baseline = route.points.reduce(0) { $0 + $1.y } / Double(route.points.count)
        let half = roadHalfWidth
        var heights = [Float](repeating: 0, count: count)
        for r in 0..<rows {
            let z = oz + Double(r) * cellSize
            for c in 0..<cols {
                let node = r * cols + c
                let x = ox + Double(c) * cellSize
                let d = Double(roadDist[node])
                let roadElev = route.points[Int(nearest[node])].y

                let farW = Interp.smoothstep(80, 900, d)
                var h = Interp.mix(roadElev, baseline, farW * 0.7)
                h += hills.fbm(x / style.hillWavelength, z / style.hillWavelength, octaves: 5)
                    * style.hillAmplitude * Interp.smoothstep(12, 320, d)
                if style.mountainAmplitude > 0 {
                    let m = peaks.fbm(x / 1500, z / 1500, octaves: 5) * 0.5 + 0.5
                    // ridged detail makes peaks look rocky
                    let ridge = 1 - abs(peaks.fbm(x / 380 + 9.1, z / 380 - 3.7, octaves: 3))
                    h += style.mountainAmplitude * pow(m, 1.6) * (0.8 + 0.2 * ridge) * Interp.smoothstep(260, 1700, d)
                }
                if style.lakeInsideLoop, inside[node], let w = route.waterLevel {
                    h = Interp.mix(h, w - 9, Interp.smoothstep(45, 260, d))
                }
                // Road bed: slightly below the road surface, blending out over ~30 m.
                let bed = roadElev - 0.45
                h = Interp.mix(bed, h, Interp.smoothstep(half + 1.0, half + 32, d))
                heights[node] = Float(h)
            }
        }

        return Terrain(
            originX: ox, originZ: oz, cellSize: cellSize, cols: cols, rows: rows, heights: heights,
            roadDistance: roadDist, nearestRoutePoint: nearest, insideLoop: inside,
            waterLevel: route.waterLevel, style: style, seed: route.seed)
    }

    // MARK: - Meshing

    /// Chunk of the terrain mesh, for frustum culling.
    public struct Chunk: Sendable {
        public var mesh: Mesh
        public var center: Vec3
    }

    /// Splits the grid into square chunks of `chunkCells` cells and builds a
    /// smooth-shaded mesh with landscape colouring for each.
    public func meshChunks(chunkCells: Int = 64) -> [Chunk] {
        // Smooth normals for all nodes.
        var normals = [Float3](repeating: Float3(0, 1, 0), count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let hl = heights[index(max(c - 1, 0), r)], hr = heights[index(min(c + 1, cols - 1), r)]
                let hd = heights[index(c, max(r - 1, 0))], hu = heights[index(c, min(r + 1, rows - 1))]
                let sx = Float(cellSize) * Float(min(c + 1, cols - 1) - max(c - 1, 0))
                let sz = Float(cellSize) * Float(min(r + 1, rows - 1) - max(r - 1, 0))
                normals[index(c, r)] = Mesh.normalize(Float3(-(hr - hl) / sx, 1, -(hu - hd) / sz))
            }
        }
        let tint = ValueNoise2D(seed: seed &+ 5)
        var chunks: [Chunk] = []
        var r0 = 0
        while r0 < rows - 1 {
            let r1 = min(r0 + chunkCells, rows - 1)
            var c0 = 0
            while c0 < cols - 1 {
                let c1 = min(c0 + chunkCells, cols - 1)
                var m = Mesh()
                let w = c1 - c0 + 1, h = r1 - r0 + 1
                m.reserve(vertices: w * h, indices: (w - 1) * (h - 1) * 6)
                var sumY = 0.0
                for r in r0...r1 {
                    for c in c0...c1 {
                        let p = nodePosition(c, r)
                        sumY += p.y
                        let n = normals[index(c, r)]
                        let color = surfaceColor(node: index(c, r), position: p, normal: n, tint: tint)
                        m.addVertex(Float3(Float(p.x), Float(p.y), Float(p.z)), normal: n, color: color)
                    }
                }
                for r in 0..<(h - 1) {
                    for c in 0..<(w - 1) {
                        let i00 = UInt32(r * w + c), i10 = i00 + 1
                        let i01 = UInt32((r + 1) * w + c), i11 = i01 + 1
                        // CCW seen from +Y (x right, z towards viewer): 00 → 01 → 11 and 00 → 11 → 10
                        m.indices.append(contentsOf: [i00, i01, i11, i00, i11, i10])
                    }
                }
                let center = Vec3(
                    originX + Double(c0 + c1) / 2 * cellSize, sumY / Double(w * h),
                    originZ + Double(r0 + r1) / 2 * cellSize)
                chunks.append(Chunk(mesh: m, center: center))
                c0 = c1
            }
            r0 = r1
        }
        return chunks
    }

    func surfaceColor(node: Int, position p: Vec3, normal n: Float3, tint: ValueNoise2D) -> Float3 {
        let d = Double(roadDistance[node])
        let v = tint.fbm(p.x / 90, p.z / 90, octaves: 3) // -1...1
        let meadow = Float3(0.40, 0.56, 0.22)
        let grass = Float3(0.27, 0.46, 0.17)
        let forestFloor = Float3(0.18, 0.31, 0.13)
        let rock = Float3(0.44, 0.42, 0.39)
        let heath = Float3(0.46, 0.43, 0.28)
        let snow = Float3(0.94, 0.95, 0.97)
        let sand = Float3(0.78, 0.71, 0.52)
        let mud = Float3(0.30, 0.28, 0.20)
        let gravel = Float3(0.52, 0.49, 0.44)

        func mix(_ a: Float3, _ b: Float3, _ t: Double) -> Float3 { a + (b - a) * Float(Interp.clamp(t, 0, 1)) }

        var col = mix(grass, meadow, 0.5 + 0.6 * v)
        col = mix(col, forestFloor, forestDensity(x: p.x, z: p.z) * 0.85)
        if let tl = style.treeLine {
            col = mix(col, heath, Interp.smoothstep(tl - 30, tl + 60, p.y + v * 25))
        }
        let slope = 1 - Double(n.y) // 0 flat … 1 vertical
        col = mix(col, rock, Interp.smoothstep(0.18, 0.34, slope + v * 0.04))
        if let sl = style.snowLine {
            let snowAmount = Interp.smoothstep(sl - 40, sl + 40, p.y + v * 40) * (1 - Interp.smoothstep(0.35, 0.5, slope))
            col = mix(col, snow, snowAmount)
        }
        if let w = waterLevel {
            col = mix(col, sand, 1 - Interp.smoothstep(w + 0.6, w + 2.2, p.y))
            col = mix(col, mud, 1 - Interp.smoothstep(w - 2.5, w - 0.5, p.y))
        }
        // gravel shoulders right next to the road
        col = mix(col, gravel, 1 - Interp.smoothstep(Terrain.roadHalfWidth + 0.5, Terrain.roadHalfWidth + 4, d))
        return col
    }
}
