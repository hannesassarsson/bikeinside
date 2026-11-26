import BikeinsideCore
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct SummaryView: View {
    let record: RideRecord
    let isNew: Bool
    @Environment(AppModel.self) private var model
    @State private var exporting = false
    @State private var ftpApplied = false

    var body: some View {
        let s = record.stats
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isNew ? "Bra kört!" : (record.workoutName ?? record.routeName))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                        Text("\(record.workoutName.map { "\($0) · " } ?? "")\(record.routeName) · \(Format.date(record.startDate))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        exporting = true
                    } label: {
                        Label("Exportera .fit", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Ladda upp filen till Strava, Garmin Connect, TrainingPeaks eller intervals.icu")
                    Button(isNew ? "Klar" : "Tillbaka") { model.closeSummary() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }

                if let ftp = record.ftpEstimate {
                    Card {
                        HStack(spacing: 16) {
                            Image(systemName: "gauge.with.dots.needle.67percent")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ny uppskattad FTP: \(Int(ftp)) W")
                                    .font(.system(size: 20, weight: .bold))
                                Text("Tidigare: \(Int(record.ftp)) W (\(ftp >= record.ftp ? "+" : "")\(Int(ftp - record.ftp)) W). \(Format.number(ftp / record.riderWeightKg, decimals: 2)) W/kg.")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if ftpApplied || Int(model.profile.ftp) == Int(ftp) {
                                Label("Sparad", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            } else {
                                Button("Använd som min FTP") {
                                    model.applyFTP(ftp)
                                    ftpApplied = true
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    }
                }

                Card {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 6), alignment: .leading, spacing: 18) {
                        StatTile(title: "Tid", value: Format.duration(Double(s.duration)))
                        StatTile(title: "Distans", value: Format.km(s.distance, decimals: 2), unit: "km")
                        StatTile(title: "Snittfart", value: Format.number(s.averageSpeed * 3.6, decimals: 1), unit: "km/h")
                        StatTile(title: "Höjdmeter", value: "\(Int(s.ascent))", unit: "m")
                        StatTile(title: "Energi", value: "\(Int(s.kilojoules))", unit: "kJ")
                        StatTile(title: "TSS", value: "\(Int(s.tss.rounded()))")
                        StatTile(title: "Snitteffekt", value: "\(Int(s.averagePower.rounded()))", unit: "W")
                        StatTile(title: "Normaliserad", value: "\(Int(s.normalizedPower.rounded()))", unit: "W")
                        StatTile(title: "Max", value: "\(s.maxPower)", unit: "W")
                        StatTile(title: "IF", value: Format.number(s.intensityFactor, decimals: 2))
                        StatTile(title: "Puls", value: s.averageHeartRate.map { "\($0)" } ?? "–", unit: s.maxHeartRate.map { "max \($0)" } ?? "", color: Theme.heart)
                        StatTile(title: "Kadens", value: s.averageCadence.map { "\($0)" } ?? "–", unit: "rpm")
                    }
                }

                if !record.samples.isEmpty {
                    SectionTitle("Effekt och höjd")
                    Card {
                        RideChart(samples: record.samples, ftp: record.ftp)
                            .frame(height: 240)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Tid i zoner")
                        Card { ZoneBars(seconds: s.timeInZones) }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Bästa effekt")
                        Card {
                            VStack(spacing: 10) {
                                if s.bestEfforts.isEmpty {
                                    Text("För kort åkning.").foregroundStyle(Theme.textSecondary)
                                }
                                ForEach(s.bestEfforts, id: \.seconds) { e in
                                    HStack {
                                        Text(effortLabel(e.seconds)).font(.system(size: 13, weight: .semibold))
                                        Spacer()
                                        Text("\(Int(e.watts.rounded())) W").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                                        Text(Format.number(e.watts / record.riderWeightKg, decimals: 1) + " W/kg")
                                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).frame(width: 70, alignment: .trailing)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if !record.segments.isEmpty {
                    SectionTitle("Segment")
                    Card {
                        VStack(spacing: 10) {
                            ForEach(Array(record.segments.enumerated()), id: \.offset) { _, r in
                                HStack {
                                    Image(systemName: r.kind == .climb ? "mountain.2.fill" : "bolt.fill")
                                        .foregroundStyle(r.kind == .climb ? Theme.accent : Theme.good)
                                    Text(r.name).font(.system(size: 14, weight: .semibold))
                                    if r.isPersonalBest {
                                        Label("PB", systemImage: "trophy.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.warn)
                                    }
                                    Spacer()
                                    Text("\(Int(r.averagePower.rounded())) W").foregroundStyle(Theme.textSecondary).monospacedDigit()
                                    Text(Format.duration(r.seconds)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .fileExporter(isPresented: $exporting, document: FITDocument(data: FITEncoder.encode(record)), contentType: .fitFile, defaultFilename: fileName) { _ in }
    }

    private var fileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "Bikeinside-\(record.routeName)-\(f.string(from: record.startDate)).fit"
    }

    private func effortLabel(_ s: Int) -> String {
        s < 60 ? "\(s) s" : "\(s / 60) min"
    }
}

struct RideChart: View {
    let samples: [RideSample]
    let ftp: Double

    /// Downsampled (max ~600 points) with a 5 s average so the chart stays readable.
    private var points: [(t: Double, power: Double, elevation: Double)] {
        let step = max(1, samples.count / 600)
        var out: [(Double, Double, Double)] = []
        var i = 0
        while i < samples.count {
            let lo = max(0, i - 2), hi = min(samples.count, i + 3)
            let avg = samples[lo..<hi].reduce(0.0) { $0 + Double($1.power) } / Double(hi - lo)
            out.append((Double(samples[i].t) / 60, avg, samples[i].elevation))
            i += step
        }
        return out
    }

    var body: some View {
        let pts = points
        let eMin = pts.map(\.elevation).min() ?? 0
        let eMax = pts.map(\.elevation).max() ?? 1
        let pMax = max(pts.map(\.power).max() ?? 1, ftp * 1.2)
        // map elevation into the power axis range for a shared chart
        func scaleE(_ e: Double) -> Double { (e - eMin) / max(eMax - eMin, 20) * pMax * 0.6 }
        Chart {
            ForEach(pts.indices, id: \.self) { i in
                AreaMark(x: .value("Minut", pts[i].t), y: .value("Höjd", scaleE(pts[i].elevation)))
                    .foregroundStyle(.white.opacity(0.10))
            }
            ForEach(pts.indices, id: \.self) { i in
                LineMark(x: .value("Minut", pts[i].t), y: .value("Watt", pts[i].power), series: .value("s", "effekt"))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("FTP", ftp))
                .foregroundStyle(.white.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("FTP \(Int(ftp)) W").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
        }
        .chartXAxisLabel("minuter")
        .chartYAxisLabel("W")
        .chartYScale(domain: 0...pMax)
    }
}

struct ZoneBars: View {
    let seconds: [Int]

    var body: some View {
        let total = max(seconds.reduce(0, +), 1)
        VStack(spacing: 7) {
            ForEach(PowerZone.allCases, id: \.self) { z in
                let s = seconds.indices.contains(z.rawValue - 1) ? seconds[z.rawValue - 1] : 0
                HStack(spacing: 10) {
                    Text("Z\(z.rawValue)").font(.system(size: 12, weight: .bold)).frame(width: 26, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(Theme.zoneColor(z))
                            .frame(width: max(4, g.size.width * CGFloat(s) / CGFloat(total)))
                    }
                    .frame(height: 10)
                    Text(Format.duration(Double(s))).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.textSecondary).frame(width: 56, alignment: .trailing)
                }
            }
        }
    }
}

extension UTType {
    static let fitFile = UTType(filenameExtension: "fit", conformingTo: .data) ?? .data
}

struct FITDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.fitFile] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
