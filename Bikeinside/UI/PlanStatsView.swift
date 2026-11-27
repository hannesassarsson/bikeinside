import BikeinsideCore
import Charts
import SwiftUI

/// Training plans with a calendar, plus long-term statistics.
struct PlanStatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Plan & statistik").font(.system(size: 30, weight: .heavy, design: .rounded))
            PlanSection()
            StatsSection()
        }
    }
}

private struct PlanSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let plan = model.activePlan {
            let sched = model.planSchedule
            let done = sched.filter(\.done).count
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.name).font(.system(size: 18, weight: .bold))
                            Text("\(done) av \(sched.count) pass klara").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Avsluta plan") { model.startPlan(nil) }.buttonStyle(SecondaryButtonStyle())
                    }
                    ProgressView(value: Double(done), total: Double(max(sched.count, 1))).tint(Theme.accent)
                    ForEach(0..<plan.weeks.count, id: \.self) { w in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("VECKA \(w + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            HStack(spacing: 8) {
                                ForEach(Array(sched.filter { $0.week == w }.enumerated()), id: \.offset) { _, s in
                                    SessionChip(item: s)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Välj en träningsplan")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(TrainingPlan.all) { p in
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(p.name).font(.system(size: 16, weight: .bold))
                                Text(p.summary).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                    .lineLimit(3, reservesSpace: true)
                                Text("\(p.weeks.reduce(0) { $0 + $1.count }) pass").font(.system(size: 12, weight: .semibold))
                                Button("Starta planen") { model.startPlan(p.id) }.buttonStyle(PrimaryButtonStyle())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

private struct SessionChip: View {
    @Environment(AppModel.self) private var model
    let item: TrainingPlan.Scheduled

    var body: some View {
        let w = WorkoutLibrary.workout(id: item.workoutId)
        let isToday = Calendar.swedish.isDateInToday(item.date)
        Button {
            model.selectedWorkoutId = item.workoutId
            model.section = .ride
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.date.formatted(.dateTime.locale(Locale(identifier: "sv_SE")).weekday(.abbreviated).day()))
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(isToday ? Theme.accent : Theme.textSecondary)
                Text(w?.name ?? item.workoutId).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.done ? Theme.good : Theme.textSecondary)
                    Text(w.map { Format.duration($0.duration) } ?? "").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(10)
            .frame(width: 150, alignment: .leading)
            .background(isToday ? Theme.accent.opacity(0.15) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isToday ? Theme.accent : .clear))
        }
        .buttonStyle(.plain)
        .help("Välj passet och gå till Cykla")
    }
}

private struct StatsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rides = model.history
        if rides.isEmpty {
            Card { Text("Statistiken fylls på när du har sparat några åkningar.").foregroundStyle(Theme.textSecondary) }
        } else {
            let load = TrainingLoad.series(rides: rides.map { ($0.startDate, $0.stats.tss) }, until: Date())
            let recent = Array(load.suffix(90))
            VStack(alignment: .leading, spacing: 16) {
                if let today = load.last {
                    Card {
                        HStack(spacing: 24) {
                            StatTile(title: "Form (TSB)", value: Format.number(today.form, decimals: 0), color: today.form >= 0 ? Theme.good : Theme.warn)
                            StatTile(title: "Kondition (CTL)", value: Format.number(today.fitness, decimals: 0))
                            StatTile(title: "Trötthet (ATL)", value: Format.number(today.fatigue, decimals: 0))
                            StatTile(title: "FTP", value: "\(Int(model.profile.ftp))", unit: "W")
                        }
                    }
                }
                SectionTitle("Belastning senaste 90 dagarna")
                Card {
                    Chart {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, d in
                            BarMark(x: .value("Dag", d.date, unit: .day), y: .value("TSS", d.tss))
                                .foregroundStyle(Theme.accent.opacity(0.35))
                            LineMark(x: .value("Dag", d.date, unit: .day), y: .value("Kondition", d.fitness), series: .value("s", "Kondition"))
                                .foregroundStyle(Theme.accentSecondary)
                            LineMark(x: .value("Dag", d.date, unit: .day), y: .value("Trötthet", d.fatigue), series: .value("s", "Trötthet"))
                                .foregroundStyle(Theme.heart)
                        }
                    }
                    .frame(height: 220)
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Bästa effekt (alla åkningar)")
                        Card {
                            let curve = TrainingLoad.powerCurve(rides.map(\.stats))
                            Chart(curve, id: \.seconds) { e in
                                BarMark(x: .value("Tid", e.seconds < 60 ? "\(e.seconds) s" : "\(e.seconds / 60) min"), y: .value("W", e.watts))
                                    .foregroundStyle(Theme.accent)
                                    .annotation(position: .top) {
                                        Text("\(Int(e.watts))").font(.system(size: 10, weight: .bold))
                                    }
                            }
                            .frame(height: 180)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("FTP-historik")
                        Card {
                            let points = rides.sorted { $0.startDate < $1.startDate }
                                .map { ($0.startDate, $0.ftpEstimate ?? $0.ftp) }
                            Chart(Array(points.enumerated()), id: \.offset) { _, p in
                                LineMark(x: .value("Datum", p.0), y: .value("FTP", p.1))
                                    .interpolationMethod(.stepEnd)
                                    .foregroundStyle(Theme.good)
                                PointMark(x: .value("Datum", p.0), y: .value("FTP", p.1)).foregroundStyle(Theme.good)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 180)
                        }
                    }
                }
            }
        }
    }
}
