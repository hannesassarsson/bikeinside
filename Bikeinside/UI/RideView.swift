import BikeinsideCore
import SwiftUI

struct RideView: View {
    @Bindable var controller: RideController
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if controller.isLoaded {
                WorldView(controller: controller)
                    .ignoresSafeArea()
            }

            if let error = controller.loadError {
                VStack(spacing: 14) {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    Button("Tillbaka") { controller.finish(save: false) }.buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            } else if !controller.isLoaded {
                LoadingView(routeName: controller.engine.route.name, progress: controller.loadProgress)
            } else {
                HUDOverlay(controller: controller)
            }

            if controller.showEndConfirm {
                EndRideDialog(controller: controller)
            } else if controller.isPaused {
                PausedOverlay(controller: controller)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in handleKey(press) }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let step: Double = press.modifiers.contains(.shift) ? 50 : 10
        switch press.key {
        case .upArrow: controller.adjustVirtualPower(step); return .handled
        case .downArrow: controller.adjustVirtualPower(-step); return .handled
        case .space: controller.togglePause(); return .handled
        case .escape:
            if controller.showEndConfirm { controller.cancelEnd() } else { controller.requestEnd() }
            return .handled
        default: break
        }
        switch press.characters.lowercased() {
        case "c": controller.cycleCamera()
        case "1": controller.cameraMode = .chase
        case "2": controller.cameraMode = .close
        case "3": controller.cameraMode = .firstPerson
        case "4": controller.cameraMode = .side
        case "5": controller.cameraMode = .drone
        case "e": controller.ergEnabled.toggle()
        case "+", "=": controller.adjustIntensity(0.05)
        case "-": controller.adjustIntensity(-0.05)
        case "n": controller.skipStep()
        case "h", "?": controller.showHelp.toggle()
        default: return .ignored
        }
        return .handled
    }
}

// MARK: - Loading

struct LoadingView: View {
    let routeName: String
    let progress: Double

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse)
            Text("Bygger \(routeName)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Terräng, skog och väg genereras…")
                .foregroundStyle(Theme.textSecondary)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(width: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

// MARK: - HUD

struct HUDOverlay: View {
    let controller: RideController

    var hud: HUDState { controller.hud }
    var ftp: Double { controller.ftp }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    if let ws = hud.workout {
                        WorkoutPanel(status: ws, ftp: ftp, intensity: controller.engine.workoutIntensity, ergEnabled: controller.ergEnabled, currentPower: hud.power3s)
                    }
                    if let seg = hud.segment {
                        SegmentPanel(segment: seg.segment, progress: seg.progress, seconds: seg.seconds, route: controller.engine.route)
                    }
                    BannerStack(banners: controller.banners)
                }
                .frame(width: 330, alignment: .leading)

                Spacer(minLength: 0)
                MainMetrics(hud: hud, ftp: ftp)
                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 12) {
                    TopRightControls(controller: controller)
                    if hud.leaderboard.count > 1 {
                        RidersPanel(rows: hud.leaderboard)
                    }
                }
                .frame(width: 330, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)

            Spacer()

            HStack(alignment: .bottom, spacing: 14) {
                StatusPanel(controller: controller)
                    .frame(width: 330, alignment: .leading)
                ElevationStrip(route: controller.engine.route, fraction: hud.routeFraction, others: hud.botRouteFractions, grade: hud.grade, elevation: hud.elevation)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 330, height: 1)
            }
            .padding(18)

            if controller.showHelp {
                HelpPanel().padding(.bottom, 18)
            }
        }
    }
}

private struct Glass: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

extension View {
    func glass(_ radius: CGFloat = 14) -> some View { modifier(Glass(radius: radius)) }
}

struct MainMetrics: View {
    let hud: HUDState
    let ftp: Double

    var body: some View {
        let zone = PowerZone.zone(power: hud.power3s, ftp: ftp)
        HStack(spacing: 0) {
            metric("km/h", Format.number(hud.speedKmh, decimals: 1))
            divider
            metric("km", Format.km(hud.distance, decimals: 2))
            divider
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(hud.power3s.rounded()))")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("W").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 6) {
                    Capsule().fill(Theme.zoneColor(zone)).frame(width: 34, height: 6)
                    Text("Z\(zone.rawValue) · \(Format.number(hud.wattsPerKg, decimals: 1)) W/kg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 210)
            divider
            metric("tid", Format.duration(hud.timerTime))
            divider
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.heart).font(.system(size: 13))
                    Text(hud.heartRate.map(String.init) ?? "–").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                }
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.accentSecondary).font(.system(size: 12))
                    Text(hud.cadence.map { "\(Int($0.rounded()))" } ?? "–").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                }
            }
            .frame(width: 96)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .glass(18)
        .overlay(alignment: .bottom) {
            if hud.draftFactor < 0.9 {
                Label("Draft −\(Int(((1 - hud.draftFactor) * 100).rounded())) %", systemImage: "wind")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accentSecondary.opacity(0.85), in: Capsule())
                    .offset(y: 12)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 48)
    }

    private func metric(_ unit: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(unit.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 96)
    }
}

struct TopRightControls: View {
    let controller: RideController

    var body: some View {
        HStack(spacing: 8) {
            Button { controller.cycleCamera() } label: {
                Label(controller.cameraMode.title, systemImage: "video.fill")
            }
            .help("Byt kamera (C eller 1–5)")
            Button { controller.togglePause() } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
            }
            .help("Pausa (mellanslag)")
            Button { controller.requestEnd() } label: {
                Image(systemName: "stop.fill")
            }
            .help("Avsluta (Esc)")
            Button { controller.showHelp.toggle() } label: {
                Image(systemName: "keyboard")
            }
            .help("Kortkommandon (H)")
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

struct WorkoutPanel: View {
    let status: RideEngine.WorkoutStatus
    let ftp: Double
    let intensity: Double
    let ergEnabled: Bool
    let currentPower: Double

    var body: some View {
        let w = status.workout
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(w.name).font(.system(size: 13, weight: .bold))
                Spacer()
                Text(ergEnabled ? "ERG" : "SIM")
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((ergEnabled ? Theme.accent : Color.gray).opacity(0.9), in: Capsule())
                    .foregroundStyle(.black)
                if abs(intensity - 1) > 0.001 {
                    Text("\(Int((intensity * 100).rounded())) %")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.warn)
                }
            }
            if status.isFinished {
                Label("Passet är klart", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.good)
            } else if let i = status.stepIndex {
                let step = w.steps[i]
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        if let t = status.targetWatts {
                            Text("\(Int(t.rounded())) W")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.zoneColor(power: t, ftp: ftp))
                        } else {
                            Text("Fritt").font(.system(size: 30, weight: .heavy, design: .rounded))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("kvar").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        Text(Format.duration(status.remainingInStep))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                if let t = status.targetWatts, !ergEnabled {
                    ComplianceBar(target: t, actual: currentPower)
                }
                if let cad = step.cadence {
                    Label("Kadens \(cad) rpm", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentSecondary)
                }
                if let next = status.nextStep {
                    Text("Nästa: \(next.label) · \(next.isFree ? "fritt" : "\(Int((next.start.watts(ftp: ftp) * intensity).rounded())) W") · \(Format.duration(next.duration))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            WorkoutChart(workout: w, ftp: ftp, progress: status.elapsed)
                .frame(height: 46)
            HStack {
                Text(Format.duration(status.elapsed))
                Spacer()
                Text(Format.duration(w.duration))
            }
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .glass()
    }
}

struct ComplianceBar: View {
    let target: Double
    let actual: Double

    var body: some View {
        let ratio = target > 0 ? actual / target : 1
        let color: Color = abs(ratio - 1) < 0.05 ? Theme.good : (abs(ratio - 1) < 0.12 ? Theme.warn : Theme.bad)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Rectangle().fill(.white.opacity(0.6)).frame(width: 2).offset(x: geo.size.width / 2 - 1)
                Circle().fill(color)
                    .frame(width: 12, height: 12)
                    .offset(x: CGFloat(Interp.clamp((ratio - 0.7) / 0.6, 0, 1)) * (geo.size.width - 12))
                    .animation(.easeOut(duration: 0.3), value: ratio)
            }
        }
        .frame(height: 12)
    }
}

struct SegmentPanel: View {
    let segment: RouteSegment
    let progress: Double
    let seconds: Double
    let route: Route

    var body: some View {
        let isClimb = segment.kind == .climb
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isClimb ? "mountain.2.fill" : "bolt.fill")
                    .foregroundStyle(isClimb ? Theme.accent : Theme.good)
                Text(segment.name).font(.system(size: 13, weight: .bold))
                Spacer()
                Text(Format.duration(seconds)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            }
            ProgressView(value: progress)
                .tint(isClimb ? Theme.accent : Theme.good)
            HStack {
                Text("\(Int((segment.length * (1 - progress)).rounded())) m kvar")
                Spacer()
                if isClimb {
                    Text("snitt \(Format.percent(route.averageGrade(from: segment.startDistance, to: segment.endDistance)))")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .glass()
    }
}

struct RidersPanel: View {
    let rows: [(name: String, gapMeters: Double, gapSeconds: Double, wattsPerKg: Double, isPlayer: Bool)]

    var body: some View {
        // show the riders closest to the player
        let idx = rows.firstIndex { $0.isPlayer } ?? 0
        let lo = max(0, idx - 3), hi = min(rows.count, idx + 4)
        VStack(alignment: .leading, spacing: 4) {
            Text("NÄRA DIG")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 2)
            ForEach(lo..<hi, id: \.self) { i in
                let r = rows[i]
                HStack(spacing: 8) {
                    Text(r.name)
                        .font(.system(size: 13, weight: r.isPlayer ? .heavy : .semibold))
                        .foregroundStyle(r.isPlayer ? Theme.accent : .white)
                        .lineLimit(1)
                    Spacer()
                    Text(Format.number(r.wattsPerKg, decimals: 1))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                    Text(r.isPlayer ? "" : Format.gap(r.gapSeconds))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                        .foregroundStyle(r.gapSeconds > 0 ? Theme.bad.opacity(0.9) : Theme.good)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(r.isPlayer ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .frame(width: 250)
        .glass()
    }
}

struct StatusPanel: View {
    let controller: RideController

    var body: some View {
        let hud = controller.hud
        VStack(alignment: .leading, spacing: 8) {
            if hud.isAutoPaused && !controller.isPaused {
                Label("Autopaus – börja trampa", systemImage: "pause.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.warn)
            }
            if controller.usesVirtualPower {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Simulerad effekt: \(Int(controller.virtualPower.rounded())) W", systemImage: "keyboard")
                        .font(.system(size: 13, weight: .bold))
                    Text("Ingen wattkälla ansluten. Styr med ↑ ↓ (shift = ±50 W).")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                HStack(spacing: 10) {
                    deviceDot(.trainer)
                    deviceDot(.powerMeter)
                    deviceDot(.heartRate)
                    deviceDot(.cadence)
                }
                if !hud.trainerMode.isEmpty, controller.bluetooth.trainerControllable {
                    Text("Trainer: \(hud.trainerMode)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let err = controller.bluetooth.trainerControlError {
                    Text(err).font(.system(size: 11)).foregroundStyle(Theme.warn)
                }
            }
            HStack(spacing: 14) {
                Label("+\(Int(hud.ascent.rounded())) m", systemImage: "arrow.up.right")
                if hud.lap > 0 { Label("Varv \(hud.lap)", systemImage: "arrow.triangle.2.circlepath") }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .glass()
    }

    @ViewBuilder
    private func deviceDot(_ role: SensorRole) -> some View {
        if let link = controller.bluetooth.links[role] {
            HStack(spacing: 4) {
                Circle().fill(link.status == .connected ? Theme.good : Theme.warn).frame(width: 7, height: 7)
                Text(link.role.displayName).font(.system(size: 11, weight: .semibold))
            }
        }
    }
}

struct ElevationStrip: View {
    let route: Route
    let fraction: Double
    let others: [Double]
    let grade: Double
    let elevation: Double

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: grade >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 14, weight: .heavy))
                Text(Format.number(grade * 100, decimals: 1) + "%")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.gradeColor(grade))
            .frame(width: 92)
            ElevationProfileView(route: route, fraction: fraction, others: others)
                .frame(height: 64)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(elevation.rounded())) m").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                Text("ö.h.").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 60)
        }
        .padding(12)
        .glass()
    }
}

struct BannerStack: View {
    let banners: [Banner]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(banners) { b in
                HStack(spacing: 10) {
                    Image(systemName: b.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(b.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(b.subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(12)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: banners)
    }
}

struct HelpPanel: View {
    var body: some View {
        let keys: [(String, String)] = [
            ("↑ / ↓", "Simulerad effekt ±10 W (shift ±50)"), ("Mellanslag", "Pausa / fortsätt"),
            ("C, 1–5", "Kameravinklar"), ("E", "ERG på/av"), ("+ / −", "Passintensitet ±5 %"),
            ("N", "Hoppa till nästa steg"), ("Esc", "Avsluta åkningen"), ("H", "Visa/dölj hjälp"),
        ]
        LazyVGrid(columns: [GridItem(.fixed(110), alignment: .trailing), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
            ForEach(keys.indices, id: \.self) { i in
                Text(keys[i].0).font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(keys[i].1).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(width: 460)
        .glass()
    }
}

struct PausedOverlay: View {
    let controller: RideController

    var body: some View {
        VStack(spacing: 16) {
            Text("Pausad").font(.system(size: 40, weight: .heavy, design: .rounded))
            HStack(spacing: 12) {
                Button("Fortsätt") { controller.togglePause() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button("Avsluta") { controller.requestEnd() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(32)
        .glass(22)
    }
}

struct EndRideDialog: View {
    let controller: RideController

    var body: some View {
        let hud = controller.hud
        VStack(spacing: 18) {
            Text("Avsluta åkningen?").font(.system(size: 28, weight: .heavy, design: .rounded))
            HStack(spacing: 28) {
                StatTile(title: "Tid", value: Format.duration(hud.timerTime))
                StatTile(title: "Distans", value: Format.km(hud.distance), unit: "km")
                StatTile(title: "Höjdmeter", value: "\(Int(hud.ascent))", unit: "m")
            }
            .frame(width: 380)
            HStack(spacing: 12) {
                Button("Spara och avsluta") { controller.finish(save: true) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button("Fortsätt cykla") { controller.cancelEnd() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Släng") { controller.finish(save: false) }
                    .buttonStyle(SecondaryButtonStyle())
                    .foregroundStyle(Theme.bad)
            }
            if hud.timerTime < 30 {
                Text("Åkningar kortare än 30 sekunder sparas inte.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(30)
        .glass(22)
    }
}
