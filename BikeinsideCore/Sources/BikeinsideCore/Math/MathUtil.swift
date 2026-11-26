import Foundation

public typealias Vec2 = SIMD2<Double>
public typealias Vec3 = SIMD3<Double>

// Methods rather than free functions so they never collide with the `simd`
// module's `length`/`normalize`/`dot` overloads when the app imports both.

extension SIMD2 where Scalar == Double {
    @inlinable public func dot(_ o: Self) -> Double { x * o.x + y * o.y }
    @inlinable public var length: Double { (x * x + y * y).squareRoot() }
    @inlinable public var normalized: Self {
        let l = length
        return l > 0 ? self / l : self
    }
    /// Left-hand perpendicular (rotated +90° in a right-handed x/y plane).
    @inlinable public var perpendicular: Self { Self(-y, x) }
}

extension SIMD3 where Scalar == Double {
    @inlinable public func dot(_ o: Self) -> Double { x * o.x + y * o.y + z * o.z }
    @inlinable public var length: Double { (x * x + y * y + z * z).squareRoot() }
    @inlinable public var normalized: Self {
        let l = length
        return l > 0 ? self / l : self
    }
    @inlinable public func cross(_ o: Self) -> Self {
        Self(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }
    /// Horizontal (x, z) components.
    @inlinable public var xz: Vec2 { Vec2(x, z) }
}

public enum Interp {
    @inlinable public static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    @inlinable public static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        x < lo ? lo : (x > hi ? hi : x)
    }

    @inlinable public static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = clamp((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Frame-rate independent exponential smoothing factor.
    /// `rate` is how many "time constants" per second.
    @inlinable public static func damp(rate: Double, dt: Double) -> Double {
        1 - exp(-rate * dt)
    }

    /// Shortest signed difference between two angles in radians.
    @inlinable public static func angleDelta(_ from: Double, _ to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }
}

/// Deterministic RNG (SplitMix64). Worlds are generated from seeds, so the same
/// route always looks the same on every machine.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
}

/// Smooth 2D value noise with fractal (fBm) sum. Output of `fbm` is roughly in [-1, 1].
public struct ValueNoise2D: Sendable {
    public let seed: UInt64

    public init(seed: UInt64) { self.seed = seed }

    @inlinable func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= seed
        h ^= h >> 33
        h &*= 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33
        h &*= 0xC4CE_B9FE_1A85_EC53
        h ^= h >> 33
        return Double(h >> 11) / Double(1 << 53) * 2 - 1
    }

    public func sample(_ x: Double, _ y: Double) -> Double {
        let xf = x.rounded(.down), yf = y.rounded(.down)
        let xi = Int(xf), yi = Int(yf)
        let tx = x - xf, ty = y - yf
        // quintic fade for C2 continuity
        let u = tx * tx * tx * (tx * (tx * 6 - 15) + 10)
        let v = ty * ty * ty * (ty * (ty * 6 - 15) + 10)
        let a = hash(xi, yi), b = hash(xi + 1, yi)
        let c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        let ab = a + (b - a) * u
        let cd = c + (d - c) * u
        return ab + (cd - ab) * v
    }

    public func fbm(_ x: Double, _ y: Double, octaves: Int = 4, lacunarity: Double = 2.0, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for o in 0..<octaves {
            // offset each octave so lattice artefacts don't line up
            let off = Double(o) * 17.13
            sum += amp * sample(x * freq + off, y * freq - off)
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return sum / norm
    }
}
