import BikeinsideCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: RideRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Historik").font(.system(size: 30, weight: .heavy, design: .rounded))
            if model.history.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inga åkningar än").font(.system(size: 16, weight: .bold))
                        Text("Dina sparade åkningar visas här, med statistik och export till Strava/Garmin (.fit).")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WeeklySummary(rides: model.history)
                VStack(spacing: 8) {
                    ForEach(model.history) { ride in
                        HistoryRow(ride: ride)
                            .onTapGesture { model.openRide(ride) }
                            .contextMenu {
                                Button("Visa") { model.openRide(ride) }
                                Button("Radera…", role: .destructive) { pendingDelete = ride }
                            }
                    }
                }
            }
        }
        .confirmationDialog("Radera åkningen?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Radera", role: .destructive) {
                if let r = pendingDelete { model.deleteRide(r) }
                pendingDelete = nil
            }
        } message: {
            Text("Det går inte att ångra.")
        }
    }
}

private struct WeeklySummary: View {
    let rides: [RideRecord]

    var body: some View {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let week = rides.filter { $0.startDate > weekAgo }
        Card {
            HStack(spacing: 24) {
                StatTile(title: "Senaste 7 dagarna", value: "\(week.count)", unit: "pass")
                StatTile(title: "Distans", value: Format.km(week.reduce(0) { $0 + $1.stats.distance }, decimals: 0), unit: "km")
                StatTile(title: "Tid", value: Format.duration(Double(week.reduce(0) { $0 + $1.stats.duration })))
                StatTile(title: "TSS", value: "\(Int(week.reduce(0) { $0 + $1.stats.tss }))")
                StatTile(title: "Energi", value: "\(Int(week.reduce(0) { $0 + $1.stats.kilojoules }))", unit: "kJ")
            }
        }
    }
}

private struct HistoryRow: View {
    let ride: RideRecord

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: ride.workoutName == nil ? "bicycle" : "chart.bar.xaxis")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.workoutName.map { "\($0) · \(ride.routeName)" } ?? ride.routeName)
                    .font(.system(size: 15, weight: .bold))
                Text(Format.date(ride.startDate)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Group {
                cell(Format.km(ride.stats.distance), "km")
                cell(Format.duration(Double(ride.stats.duration)), "tid")
                cell("\(Int(ride.stats.averagePower))", "W snitt")
                cell("\(Int(ride.stats.tss))", "TSS")
            }
            if ride.segments.contains(where: \.isPersonalBest) {
                Image(systemName: "trophy.fill").foregroundStyle(Theme.warn).help("Personbästa på segment")
            }
            Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func cell(_ v: String, _ unit: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(v).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 70, alignment: .trailing)
    }
}
