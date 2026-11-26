import BikeinsideCore
import SwiftUI

/// Filled elevation profile with the rider (and optionally others) marked.
struct ElevationProfileView: View {
    let route: Route
    var fraction: Double?
    var others: [Double] = []
    var color: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            let profile = route.elevationProfile(count: max(Int(size.width / 2), 20))
            let lo = (profile.min() ?? 0), hi = (profile.max() ?? 1)
            let range = max(hi - lo, 30) // keep flat routes looking flat
            func pt(_ i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(profile.count - 1) * size.width
                let y = size.height - CGFloat((profile[i] - lo) / range) * (size.height - 6) - 3
                return CGPoint(x: x, y: y)
            }
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            for i in profile.indices { area.addLine(to: pt(i)) }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.55), color.opacity(0.08)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var line = Path()
            line.move(to: pt(0))
            for i in profile.indices.dropFirst() { line.addLine(to: pt(i)) }
            ctx.stroke(line, with: .color(color), lineWidth: 1.5)

            // segments
            for seg in route.segments {
                let x0 = seg.startDistance / route.length * size.width
                let x1 = seg.endDistance / route.length * size.width
                let c: Color = seg.kind == .climb ? Theme.accent : Theme.good
                ctx.fill(Path(CGRect(x: x0, y: size.height - 3, width: max(x1 - x0, 2), height: 3)), with: .color(c))
            }

            func marker(_ f: Double, _ c: Color, _ r: CGFloat) {
                let i = Int((Interp.clamp(f, 0, 1) * Double(profile.count - 1)).rounded())
                let p = pt(i)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(c))
            }
            for o in others { marker(o, .white.opacity(0.75), 3) }
            if let f = fraction {
                let i = Int((Interp.clamp(f, 0, 1) * Double(profile.count - 1)).rounded())
                let p = pt(i)
                ctx.stroke(Path { $0.move(to: CGPoint(x: p.x, y: 0)); $0.addLine(to: CGPoint(x: p.x, y: size.height)) },
                           with: .color(.white.opacity(0.35)), lineWidth: 1)
                marker(f, .white, 6)
                marker(f, color, 4)
            }
        }
    }
}

/// Block chart of a workout coloured by power zone, with optional progress.
struct WorkoutChart: View {
    let workout: Workout
    let ftp: Double
    var progress: Double?

    var body: some View {
        Canvas { ctx, size in
            let total = max(workout.duration, 1)
            let peak = max(workout.peakFraction(ftp: ftp), 1.2)
            var t = 0.0
            for s in workout.steps {
                let x0 = t / total * size.width
                let x1 = (t + s.duration) / total * size.width
                let f0 = s.isFree ? 1.0 : s.start.fraction(ftp: ftp)
                let f1 = s.isFree ? 1.0 : s.end.fraction(ftp: ftp)
                let y0 = size.height - CGFloat(f0 / peak) * size.height
                let y1 = size.height - CGFloat(f1 / peak) * size.height
                var p = Path()
                p.move(to: CGPoint(x: x0, y: size.height))
                p.addLine(to: CGPoint(x: x0, y: y0))
                p.addLine(to: CGPoint(x: x1, y: y1))
                p.addLine(to: CGPoint(x: x1, y: size.height))
                p.closeSubpath()
                let zone = PowerZone.zone(power: (f0 + f1) / 2 * ftp, ftp: ftp)
                let col = s.isFree ? Color.white.opacity(0.5) : Theme.zoneColor(zone)
                ctx.fill(p, with: .color(col.opacity(0.9)))
                t += s.duration
            }
            // FTP line
            let fy = size.height - CGFloat(1 / peak) * size.height
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: fy)); $0.addLine(to: CGPoint(x: size.width, y: fy)) },
                       with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let progress {
                let x = CGFloat(min(progress / total, 1)) * size.width
                ctx.fill(Path(CGRect(x: 0, y: 0, width: x, height: size.height)), with: .color(.black.opacity(0.45)))
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
            }
        }
    }
}
