import AppKit
import BikeinsideCore

/// Sky, sun and haze for each landscape theme.
struct Atmosphere {
    var zenith: SIMD3<Double>
    var horizon: SIMD3<Double>
    /// Direction the sunlight travels (from the sun towards the ground).
    var sunDirection: SIMD3<Float>
    var sunColor: NSColor
    /// Illuminance in lux for RealityKit's directional light.
    var sunIntensity: Float
    /// Exponent applied to the sky-based ambient light.
    var ambientExponent: Float
    var fogEnd: Float
    var cloudiness: Double

    static func forTheme(_ theme: SceneryTheme) -> Atmosphere {
        switch theme {
        case .forest:
            return Atmosphere(
                zenith: SIMD3(0.22, 0.45, 0.82), horizon: SIMD3(0.74, 0.83, 0.91),
                sunDirection: SIMD3(-0.45, -0.78, -0.35), sunColor: NSColor(calibratedRed: 1, green: 0.96, blue: 0.88, alpha: 1),
                sunIntensity: 9000, ambientExponent: 1.0, fogEnd: 1500, cloudiness: 0.45)
        case .lake:
            return Atmosphere(
                zenith: SIMD3(0.28, 0.42, 0.75), horizon: SIMD3(0.95, 0.80, 0.64),
                sunDirection: SIMD3(0.55, -0.42, -0.6), sunColor: NSColor(calibratedRed: 1, green: 0.84, blue: 0.66, alpha: 1),
                sunIntensity: 8000, ambientExponent: 0.9, fogEnd: 2000, cloudiness: 0.3)
        case .mountain:
            return Atmosphere(
                zenith: SIMD3(0.12, 0.32, 0.72), horizon: SIMD3(0.72, 0.81, 0.92),
                sunDirection: SIMD3(-0.3, -0.7, 0.55), sunColor: NSColor(calibratedRed: 1, green: 0.97, blue: 0.92, alpha: 1),
                sunIntensity: 10000, ambientExponent: 1.0, fogEnd: 3200, cloudiness: 0.25)
        }
    }

    /// Horizon colour in linear space (for the fog shader).
    var fogLinear: SIMD3<Float> {
        SIMD3(Float(pow(horizon.x, 2.2)), Float(pow(horizon.y, 2.2)), Float(pow(horizon.z, 2.2)))
    }

    /// Equirectangular sky (2:1) with a vertical gradient and soft procedural clouds.
    func skyImage(seed: UInt64, width w: Int = 1024) -> CGImage? {
        let h = w / 2
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        let noise = ValueNoise2D(seed: seed)
        for y in 0..<h {
            let elev = (0.5 - (Double(y) + 0.5) / Double(h)) * .pi // +π/2 top … −π/2 bottom
            let up = max(sin(elev), 0)
            let base: SIMD3<Double> = elev >= 0 ? horizon + (zenith - horizon) * pow(up, 0.45) : horizon * 0.98
            for x in 0..<w {
                var c = base
                if elev > 0.02 && cloudiness > 0 {
                    let u = Double(x) / Double(w) * 2 * .pi
                    // project onto a cloud plane so clouds flatten towards the horizon
                    let r = 1 / max(sin(elev), 0.08)
                    let n = noise.fbm(cos(u) * r * 1.2 + 10, sin(u) * r * 1.2 - 4, octaves: 5) * 0.5 + 0.5
                    let cover = Interp.smoothstep(1 - cloudiness * 0.9, 1.05 - cloudiness * 0.5, n)
                    let fade = Interp.smoothstep(0.02, 0.25, elev)
                    let cloud = SIMD3<Double>(0.97, 0.97, 0.98) * (0.86 + 0.14 * up)
                    c = c + (cloud - c) * (cover * fade * 0.85)
                }
                let i = (y * w + x) * 4
                pixels[i] = UInt8(Interp.clamp(c.x, 0, 1) * 255)
                pixels[i + 1] = UInt8(Interp.clamp(c.y, 0, 1) * 255)
                pixels[i + 2] = UInt8(Interp.clamp(c.z, 0, 1) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
