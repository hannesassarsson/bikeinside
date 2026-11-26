import Foundation

public typealias Float3 = SIMD3<Float>

/// GPU-ready triangle mesh with per-vertex colour. The app converts it to an
/// `SCNGeometry`; everything else (terrain, road, trees, houses) is generated
/// here so it is deterministic and unit-testable.
public struct Mesh: Sendable {
    public var positions: [Float3] = []
    public var normals: [Float3] = []
    public var colors: [Float3] = []
    public var indices: [UInt32] = []

    public init() {}

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { indices.isEmpty }

    public mutating func reserve(vertices: Int, indices n: Int) {
        positions.reserveCapacity(vertices)
        normals.reserveCapacity(vertices)
        colors.reserveCapacity(vertices)
        indices.reserveCapacity(n)
    }

    /// Adds a vertex and returns its index.
    @discardableResult
    public mutating func addVertex(_ p: Float3, normal: Float3, color: Float3) -> UInt32 {
        positions.append(p)
        normals.append(normal)
        colors.append(color)
        return UInt32(positions.count - 1)
    }

    /// Flat-shaded triangle (counter-clockwise front face, seen from outside).
    public mutating func addTriangle(_ a: Float3, _ b: Float3, _ c: Float3, color: Float3) {
        let n = Mesh.faceNormal(a, b, c)
        let i = addVertex(a, normal: n, color: color)
        addVertex(b, normal: n, color: color)
        addVertex(c, normal: n, color: color)
        indices.append(contentsOf: [i, i + 1, i + 2])
    }

    /// Flat-shaded quad a-b-c-d (counter-clockwise).
    public mutating func addQuad(_ a: Float3, _ b: Float3, _ c: Float3, _ d: Float3, color: Float3) {
        let n = Mesh.faceNormal(a, b, c)
        let i = addVertex(a, normal: n, color: color)
        addVertex(b, normal: n, color: color)
        addVertex(c, normal: n, color: color)
        addVertex(d, normal: n, color: color)
        indices.append(contentsOf: [i, i + 1, i + 2, i, i + 2, i + 3])
    }

    /// Appends another mesh after scaling, rotating about Y and translating it.
    /// `tint` multiplies vertex colours, giving instances some variety.
    public mutating func append(_ m: Mesh, transform t: MeshTransform = .identity, tint: Float3 = Float3(1, 1, 1)) {
        let base = UInt32(positions.count)
        let c = cos(t.yaw), s = sin(t.yaw)
        let invScale = Float3(1 / t.scale.x, 1 / t.scale.y, 1 / t.scale.z)
        for k in 0..<m.positions.count {
            let p = m.positions[k] * t.scale
            positions.append(Float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z) + t.translation)
            var n = m.normals[k] * invScale
            n = Float3(c * n.x + s * n.z, n.y, -s * n.x + c * n.z)
            normals.append(Mesh.normalize(n))
            colors.append(m.colors[k] * tint)
        }
        indices.append(contentsOf: m.indices.map { $0 + base })
    }

    public static func faceNormal(_ a: Float3, _ b: Float3, _ c: Float3) -> Float3 {
        let u = b - a, v = c - a
        return normalize(Float3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x))
    }

    public static func normalize(_ v: Float3) -> Float3 {
        let l = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        return l > 1e-12 ? v / l : Float3(0, 1, 0)
    }

    /// Axis-aligned bounds (min, max); zero box for an empty mesh.
    public var bounds: (min: Float3, max: Float3) {
        guard var lo = positions.first else { return (Float3(), Float3()) }
        var hi = lo
        for p in positions {
            lo = Float3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = Float3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        return (lo, hi)
    }
}

public struct MeshTransform: Sendable {
    public var translation: Float3
    /// Rotation about +Y in radians (right-handed: +X turns towards -Z).
    public var yaw: Float
    public var scale: Float3

    public init(translation: Float3 = Float3(), yaw: Float = 0, scale: Float3 = Float3(1, 1, 1)) {
        self.translation = translation
        self.yaw = yaw
        self.scale = scale
    }

    public init(translation: Float3, yaw: Float, uniformScale: Float) {
        self.init(translation: translation, yaw: yaw, scale: Float3(repeating: uniformScale))
    }

    public static let identity = MeshTransform()
}

/// Low-poly building blocks. All are built around the origin with +Y up and
/// sit on y = 0 unless noted.
public enum Primitives {
    /// Open-ended cylinder/frustum (no caps), `sides` facets.
    public static func frustum(
        into m: inout Mesh, center: Float3, bottomRadius: Float, topRadius: Float, height: Float,
        sides: Int, color: Float3, capTop: Bool = false
    ) {
        for k in 0..<sides {
            let a0 = Float(k) / Float(sides) * 2 * .pi
            let a1 = Float(k + 1) / Float(sides) * 2 * .pi
            let b0 = center + Float3(cos(a0) * bottomRadius, 0, -sin(a0) * bottomRadius)
            let b1 = center + Float3(cos(a1) * bottomRadius, 0, -sin(a1) * bottomRadius)
            let t0 = center + Float3(cos(a0) * topRadius, height, -sin(a0) * topRadius)
            let t1 = center + Float3(cos(a1) * topRadius, height, -sin(a1) * topRadius)
            if topRadius <= 0.0001 {
                if height >= 0 {
                    m.addTriangle(b0, b1, center + Float3(0, height, 0), color: color)
                } else {
                    m.addTriangle(b1, b0, center + Float3(0, height, 0), color: color)
                }
            } else {
                m.addQuad(b0, b1, t1, t0, color: color)
                if capTop {
                    m.addTriangle(t0, t1, center + Float3(0, height, 0), color: color)
                }
            }
        }
    }

    /// Axis-aligned box from min to max corner.
    public static func box(into m: inout Mesh, min a: Float3, max b: Float3, color: Float3, bottom: Bool = false) {
        let p000 = Float3(a.x, a.y, a.z), p100 = Float3(b.x, a.y, a.z)
        let p010 = Float3(a.x, b.y, a.z), p110 = Float3(b.x, b.y, a.z)
        let p001 = Float3(a.x, a.y, b.z), p101 = Float3(b.x, a.y, b.z)
        let p011 = Float3(a.x, b.y, b.z), p111 = Float3(b.x, b.y, b.z)
        m.addQuad(p001, p101, p111, p011, color: color) // +z
        m.addQuad(p100, p000, p010, p110, color: color) // -z
        m.addQuad(p101, p100, p110, p111, color: color) // +x
        m.addQuad(p000, p001, p011, p010, color: color) // -x
        m.addQuad(p011, p111, p110, p010, color: color) // +y
        if bottom { m.addQuad(p000, p100, p101, p001, color: color) }
    }

    /// Low-poly sphere (icosahedron, optionally subdivided once), flat shaded.
    /// `jitter` randomly displaces vertices for organic shapes (rocks, crowns).
    public static func blob(
        into m: inout Mesh, center: Float3, radius: Float3, color: Float3,
        subdivide: Bool = false, jitter: Float = 0, seed: UInt64 = 1
    ) {
        let t: Float = (1 + Float(5).squareRoot()) / 2
        var verts: [Float3] = [
            Float3(-1, t, 0), Float3(1, t, 0), Float3(-1, -t, 0), Float3(1, -t, 0),
            Float3(0, -1, t), Float3(0, 1, t), Float3(0, -1, -t), Float3(0, 1, -t),
            Float3(t, 0, -1), Float3(t, 0, 1), Float3(-t, 0, -1), Float3(-t, 0, 1),
        ].map { Mesh.normalize($0) }
        var faces: [(Int, Int, Int)] = [
            (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
            (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
            (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
            (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
        ]
        if subdivide {
            var cache: [Int: Int] = [:]
            func mid(_ a: Int, _ b: Int) -> Int {
                let key = a < b ? a * 1000 + b : b * 1000 + a
                if let v = cache[key] { return v }
                verts.append(Mesh.normalize((verts[a] + verts[b]) / 2))
                cache[key] = verts.count - 1
                return verts.count - 1
            }
            var nf: [(Int, Int, Int)] = []
            for (a, b, c) in faces {
                let ab = mid(a, b), bc = mid(b, c), ca = mid(c, a)
                nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            }
            faces = nf
        }
        if jitter > 0 {
            var rng = SeededRandom(seed: seed)
            verts = verts.map { $0 * (1 + Float(rng.range(-1, 1)) * jitter) }
        }
        for (a, b, c) in faces {
            m.addTriangle(center + verts[a] * radius, center + verts[b] * radius, center + verts[c] * radius, color: color)
        }
    }

    // MARK: Prototypes (unit-ish size; scaled per instance)

    /// Norway spruce ("gran"): ~16 m tall at scale 1.
    public static func spruce(detail: Bool) -> Mesh {
        var m = Mesh()
        let bark = Float3(0.30, 0.21, 0.14)
        let needles = Float3(0.11, 0.27, 0.14)
        frustum(into: &m, center: Float3(), bottomRadius: 0.35, topRadius: 0.2, height: 3, sides: detail ? 5 : 3, color: bark)
        if detail {
            let tiers: [(y: Float, r: Float, h: Float, shade: Float)] = [
                (1.8, 3.2, 7.0, 0.85), (5.6, 2.4, 6.4, 1.0), (9.4, 1.5, 5.6, 1.15),
            ]
            for t in tiers {
                frustum(into: &m, center: Float3(0, t.y, 0), bottomRadius: t.r, topRadius: 0, height: t.h, sides: 6, color: needles * t.shade)
            }
        } else {
            frustum(into: &m, center: Float3(0, 1.8, 0), bottomRadius: 3.0, topRadius: 0, height: 14, sides: 5, color: needles)
        }
        return m
    }

    /// Scots pine ("tall"): tall bare orange trunk with a flat crown.
    public static func pine(detail: Bool) -> Mesh {
        var m = Mesh()
        let bark = Float3(0.62, 0.36, 0.20)
        let crown = Float3(0.20, 0.36, 0.17)
        frustum(into: &m, center: Float3(), bottomRadius: 0.35, topRadius: 0.22, height: 11, sides: detail ? 6 : 4, color: bark)
        blob(into: &m, center: Float3(0, 12.5, 0), radius: Float3(3.4, 2.4, 3.4), color: crown, subdivide: false, jitter: detail ? 0.18 : 0, seed: 3)
        return m
    }

    /// Silver birch ("björk"): white trunk with dark marks and a light green crown.
    public static func birch(detail: Bool) -> Mesh {
        var m = Mesh()
        let white = Float3(0.90, 0.89, 0.85)
        let dark = Float3(0.15, 0.14, 0.13)
        let leaves = Float3(0.42, 0.62, 0.22)
        frustum(into: &m, center: Float3(), bottomRadius: 0.22, topRadius: 0.16, height: 4, sides: 5, color: white)
        if detail {
            frustum(into: &m, center: Float3(0, 4, 0), bottomRadius: 0.16, topRadius: 0.15, height: 0.35, sides: 5, color: dark)
        }
        frustum(into: &m, center: Float3(0, 4.35, 0), bottomRadius: 0.15, topRadius: 0.09, height: 5, sides: 5, color: white)
        blob(into: &m, center: Float3(0, 8.6, 0), radius: Float3(2.6, 3.6, 2.6), color: leaves, subdivide: false, jitter: detail ? 0.14 : 0.05, seed: 9)
        return m
    }

    public static func rock(seed: UInt64) -> Mesh {
        var m = Mesh()
        blob(into: &m, center: Float3(0, 0.25, 0), radius: Float3(1.0, 0.7, 0.85), color: Float3(0.50, 0.49, 0.47), jitter: 0.25, seed: seed)
        return m
    }

    /// Red Swedish cottage with white trim ("röd stuga"). ~8 x 6 m footprint.
    public static func cottage(roofColor: Float3 = Float3(0.20, 0.18, 0.18)) -> Mesh {
        var m = Mesh()
        let red = Float3(0.56, 0.11, 0.08)
        let white = Float3(0.93, 0.92, 0.88)
        let w: Float = 4, d: Float = 3, wallH: Float = 3.2, ridgeH: Float = 5.6
        box(into: &m, min: Float3(-w, -1.5, -d), max: Float3(w, wallH, d), color: red)
        // gables
        m.addTriangle(Float3(-w, wallH, d), Float3(w, wallH, d), Float3(0, ridgeH, d), color: red)
        m.addTriangle(Float3(w, wallH, -d), Float3(-w, wallH, -d), Float3(0, ridgeH, -d), color: red)
        // roof with overhang
        let o: Float = 0.5
        m.addQuad(Float3(-w - o, wallH - 0.3, d + o), Float3(0, ridgeH + 0.1, d + o), Float3(0, ridgeH + 0.1, -d - o), Float3(-w - o, wallH - 0.3, -d - o), color: roofColor)
        m.addQuad(Float3(0, ridgeH + 0.1, d + o), Float3(w + o, wallH - 0.3, d + o), Float3(w + o, wallH - 0.3, -d - o), Float3(0, ridgeH + 0.1, -d - o), color: roofColor)
        // white corner boards
        for (x, z) in [(-w, -d), (w, -d), (-w, d), (w, d)] {
            box(into: &m, min: Float3(x - 0.12, 0, z - 0.12), max: Float3(x + 0.12, wallH, z + 0.12), color: white)
        }
        // windows (white frames) on the long sides and a door
        for x in [Float(-2.4), 2.4] {
            box(into: &m, min: Float3(x - 0.6, 1.1, d), max: Float3(x + 0.6, 2.3, d + 0.08), color: white)
            box(into: &m, min: Float3(x - 0.45, 1.25, d + 0.02), max: Float3(x + 0.45, 2.15, d + 0.1), color: Float3(0.12, 0.16, 0.22))
            box(into: &m, min: Float3(x - 0.6, 1.1, -d - 0.08), max: Float3(x + 0.6, 2.3, -d), color: white)
        }
        box(into: &m, min: Float3(-0.55, 0, d), max: Float3(0.55, 2.2, d + 0.1), color: white)
        box(into: &m, min: Float3(-0.4, 0, d + 0.02), max: Float3(0.4, 2.05, d + 0.14), color: Float3(0.36, 0.22, 0.12))
        // chimney
        box(into: &m, min: Float3(1.5, wallH + 0.8, -0.4), max: Float3(2.2, ridgeH + 0.9, 0.3), color: Float3(0.45, 0.40, 0.36))
        return m
    }

    /// Flagpole with a Swedish flag (blue with a yellow Nordic cross).
    public static func flagpole() -> Mesh {
        var m = Mesh()
        let white = Float3(0.95, 0.95, 0.95)
        frustum(into: &m, center: Float3(), bottomRadius: 0.07, topRadius: 0.05, height: 9, sides: 5, color: white)
        blob(into: &m, center: Float3(0, 9.05, 0), radius: Float3(0.12, 0.12, 0.12), color: Float3(0.85, 0.7, 0.2))
        let blue = Float3(0.0, 0.32, 0.62), yellow = Float3(1.0, 0.80, 0.0)
        // flag 2.5 x 1.6 m in the x/y plane, double-sided, cross offset towards the pole
        let x0: Float = 0.08, top: Float = 8.9, h: Float = 1.6, len: Float = 2.5
        let cv0: Float = x0 + 0.62, cv1: Float = cv0 + 0.32 // vertical bar
        let ch0: Float = top - h / 2 - 0.16, ch1: Float = top - h / 2 + 0.16 // horizontal bar
        func rect(_ a: Float, _ b: Float, _ y0: Float, _ y1: Float, _ c: Float3) {
            m.addQuad(Float3(a, y0, 0), Float3(b, y0, 0), Float3(b, y1, 0), Float3(a, y1, 0), color: c)
            m.addQuad(Float3(b, y0, 0), Float3(a, y0, 0), Float3(a, y1, 0), Float3(b, y1, 0), color: c)
        }
        let bottom = top - h
        rect(x0, cv0, bottom, ch0, blue); rect(x0, cv0, ch1, top, blue)
        rect(cv1, x0 + len, bottom, ch0, blue); rect(cv1, x0 + len, ch1, top, blue)
        rect(cv0, cv1, bottom, top, yellow)
        rect(x0, cv0, ch0, ch1, yellow); rect(cv1, x0 + len, ch0, ch1, yellow)
        return m
    }

    /// Banner arch spanning the road, centred on the origin, spanning ±halfWidth on X.
    /// `checkered` alternates black/white blocks (start/finish line).
    public static func arch(halfWidth: Float, color: Float3, checkered: Bool) -> Mesh {
        var m = Mesh()
        let post = Float3(0.85, 0.85, 0.85)
        for x in [-halfWidth, halfWidth] {
            box(into: &m, min: Float3(x - 0.2, -1, -0.2), max: Float3(x + 0.2, 6.2, 0.2), color: post)
        }
        let blocks = 16
        let w = 2 * halfWidth / Float(blocks)
        for k in 0..<blocks {
            let x0 = -halfWidth + Float(k) * w
            for row in 0..<2 {
                let y0: Float = 5.0 + Float(row) * 0.6
                let c: Float3
                if checkered {
                    c = (k + row) % 2 == 0 ? Float3(0.08, 0.08, 0.08) : Float3(0.95, 0.95, 0.95)
                } else {
                    c = (k % 4 == 0) ? Float3(0.95, 0.95, 0.95) : color
                }
                box(into: &m, min: Float3(x0, y0, -0.15), max: Float3(x0 + w, y0 + 0.6, 0.15), color: c)
            }
        }
        return m
    }
}
