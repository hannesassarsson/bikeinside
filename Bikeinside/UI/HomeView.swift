import BikeinsideCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(AppModel.Section.allCases, selection: Binding<AppModel.Section?>(
                get: { model.section },
                set: { if let v = $0 { model.section = v } })
            ) { s in
                Label(s.title, systemImage: s.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.vertical, 4)
                    .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("Bikeinside")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom) {
                DeviceSummary()
                    .padding(12)
            }
        } detail: {
            ScrollView {
                Group {
                    switch model.section {
                    case .ride: StartRideView()
                    case .workouts: WorkoutsView()
                    case .history: HistoryView()
                    case .devices: DevicesView()
                    case .profile: ProfileView()
                    }
                }
                .padding(28)
                .padding(.top, 10)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
        }
    }
}

/// Compact device status in the sidebar.
struct DeviceSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bt = model.bluetooth
        VStack(alignment: .leading, spacing: 6) {
            if let msg = bt.radio.message {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warn)
            } else if bt.links.isEmpty {
                Label("Inga enheter anslutna", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(SensorRole.allCases, id: \.self) { role in
                    if let l = bt.links[role] {
                        HStack(spacing: 6) {
                            Circle().fill(l.status == .connected ? Theme.good : Theme.warn).frame(width: 7, height: 7)
                            Text(l.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(l.lastValue).font(.system(size: 10)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture { model.section = .devices }
    }
}

// MARK: - Start ride

struct StartRideView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 26) {
            header

            SectionTitle("Välj värld")
            HStack(spacing: 16) {
                ForEach(RouteLibrary.all, id: \.id) { bp in
                    RouteCard(route: model.route(id: bp.id), selected: model.selectedRouteId == bp.id)
                        .onTapGesture { model.selectedRouteId = bp.id }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Läge")
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("", selection: Binding(
                                get: { model.selectedWorkoutId == nil ? 0 : 1 },
                                set: { v in
                                    if v == 0 { model.selectedWorkoutId = nil }
                                    else if model.selectedWorkoutId == nil { model.section = .workouts }
                                })
                            ) {
                                Text("Fri cykling").tag(0)
                                Text("Träningspass").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            if let w = model.selectedWorkout {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.name).font(.system(size: 15, weight: .bold))
                                        Text("\(Format.duration(w.duration)) · TSS \(Int(w.estimatedTSS(ftp: model.profile.ftp)))")
                                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Button("Byt pass") { model.section = .workouts }
                                        .buttonStyle(SecondaryButtonStyle())
                                }
                                WorkoutChart(workout: w, ftp: model.profile.ftp).frame(height: 54)
                            } else {
                                Text("Cykla fritt. Trainern känner av backarna i världen.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Medcyklister")
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Grupp", selection: $model.settings.paceGroup) {
                                ForEach(PaceGroup.allCases) { g in
                                    Text(g == .none ? g.title : "\(g.title) · \(Format.number(g.wattsPerKg, decimals: 1)) W/kg").tag(g)
                                }
                            }
                            .labelsHidden()
                            Text(model.settings.paceGroup == .none
                                 ? "Du har vägen för dig själv."
                                 : "Sex datorstyrda cyklister. Lägg dig bakom en rygg så sparar du ~30 % luftmotstånd.")
                                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            Divider().opacity(0.3)
                            HStack {
                                Text("Trainerkänsla").font(.system(size: 13, weight: .semibold))
                                Slider(value: $model.settings.trainerDifficulty, in: 0...1, step: 0.05)
                                Text("\(Int(model.settings.trainerDifficulty * 100)) %").monospacedDigit().frame(width: 44)
                            }
                            .help("Hur mycket av backarnas lutning trainern återger. Hastigheten i spelet påverkas inte.")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                ReadinessHint()
                Spacer()
                Button {
                    model.startRide()
                } label: {
                    Label("Starta åkningen", systemImage: "play.fill")
                        .padding(.horizontal, 12)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hej \(model.profile.name)!")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("FTP \(Int(model.profile.ftp)) W · \(Format.number(model.profile.wattsPerKgAtFTP, decimals: 2)) W/kg")
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(spacing: 24) {
                StatTile(title: "Åkningar", value: "\(model.history.count)")
                StatTile(title: "Totalt", value: Format.number(model.totalDistanceKm, decimals: 0), unit: "km")
                StatTile(title: "Tid", value: Format.number(model.totalHours, decimals: 1), unit: "h")
            }
            .frame(width: 360)
        }
    }
}

struct ReadinessHint: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bt = model.bluetooth
        if bt.links[.trainer] == nil && bt.links[.powerMeter] == nil {
            Label("Ingen trainer ansluten – du kan cykla med simulerad effekt (piltangenterna).", systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        } else if let t = bt.links[.trainer], t.status != .connected {
            Label("Väntar på \(t.name)… trampa ett varv för att väcka den.", systemImage: "hourglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.warn)
        } else {
            Label("Redo att cykla!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.good)
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.textSecondary)
    }
}

struct RouteCard: View {
    let route: Route
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: themeColors, startPoint: .top, endPoint: .bottom)
                ElevationProfileView(route: route, color: .white)
                    .padding(.top, 34)
                Text(themeName)
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(10)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(route.name).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(route.summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3, reservesSpace: true)
            HStack(spacing: 14) {
                Label("\(Format.km(route.length)) km", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label("\(Int(route.totalAscent)) m", systemImage: "arrow.up.right")
                Label("max \(Format.number(route.maxGrade * 100, decimals: 0)) %", systemImage: "chart.line.uptrend.xyaxis")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(selected ? Theme.panelHighlight : Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Theme.accent : .white.opacity(0.06), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var themeName: String {
        switch route.theme {
        case .forest: return "SKOG"
        case .lake: return "SJÖ"
        case .mountain: return "FJÄLL"
        }
    }

    private var themeColors: [Color] {
        switch route.theme {
        case .forest: return [Color(red: 0.25, green: 0.45, blue: 0.75), Color(red: 0.13, green: 0.35, blue: 0.20)]
        case .lake: return [Color(red: 0.95, green: 0.62, blue: 0.40), Color(red: 0.12, green: 0.32, blue: 0.48)]
        case .mountain: return [Color(red: 0.35, green: 0.55, blue: 0.85), Color(red: 0.40, green: 0.42, blue: 0.48)]
        }
    }
}
