import Foundation

/// Built-in structured workouts, all relative to the rider's FTP.
public enum WorkoutLibrary {
    public static let all: [Workout] = [
        recoverySpin, enduranceHour, tempo3x12, sweetSpot3x10, overUnder, threshold2x20,
        vo2max5x3, microBursts, sprints, pyramid, rampTest, twentyMinuteTest,
    ]

    public static func workout(id: String) -> Workout? { all.first { $0.id == id } }

    public static let recoverySpin: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 5, from: 0.4, to: 0.5)
        b.steady(minutes: 20, at: 0.52, label: "Lätt trampande", cadence: 90)
        b.cooldown(minutes: 5, from: 0.5, to: 0.4)
        return Workout(id: "recovery-30", name: "Lätt återhämtning", summary: "30 minuter lugn rullning med hög kadens. Perfekt dagen efter ett hårt pass.", category: .recovery, steps: b.steps)
    }()

    public static let enduranceHour: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 10)
        for k in 0..<4 {
            b.steady(minutes: 9, at: 0.68, label: "Distans")
            b.steady(seconds: 60, at: 0.78, label: k.isMultiple(of: 2) ? "Kadenslyft" : "Lite tryck", cadence: k.isMultiple(of: 2) ? 105 : nil)
        }
        b.cooldown(minutes: 10)
        return Workout(id: "endurance-60", name: "Distanstimmen", summary: "En timme i zon 2 med korta lyft. Bygger grunden.", category: .endurance, steps: b.steps)
    }()

    public static let tempo3x12: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 10)
        b.intervals(3, on: 12 * 60, at: 0.82, off: 4 * 60, at: 0.55, label: "Tempo")
        b.cooldown(minutes: 6)
        return Workout(id: "tempo-3x12", name: "Tempo 3×12", summary: "Tre block i tempofart. Stadigt och kontrollerat.", category: .tempo, steps: b.steps)
    }()

    public static let sweetSpot3x10: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 10)
        b.steady(minutes: 2, at: 0.75, label: "Förberedelse")
        b.recover(seconds: 120)
        b.intervals(3, on: 10 * 60, at: 0.90, off: 5 * 60, at: 0.55, label: "Sweet spot")
        b.cooldown(minutes: 8)
        return Workout(id: "sweetspot-3x10", name: "Sweet spot 3×10", summary: "Klassisk sweet spot på 88–94 % av FTP. Mycket träning för pengarna.", category: .tempo, steps: b.steps)
    }()

    public static let overUnder: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 10)
        for set in 1...3 {
            for k in 0..<3 {
                b.steady(seconds: 120, at: 0.95, label: "Under \(set)/3")
                b.steady(seconds: 60, at: 1.07, label: "Över \(set)/3")
                _ = k
            }
            b.recover(seconds: 300, at: 0.5)
        }
        b.cooldown(minutes: 6)
        return Workout(id: "over-under", name: "Över–under", summary: "Växla strax under och strax över tröskeln. Lär kroppen att hantera mjölksyra.", category: .threshold, steps: b.steps)
    }()

    public static let threshold2x20: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 12)
        b.intervals(2, on: 20 * 60, at: 0.96, off: 6 * 60, at: 0.5, label: "Tröskel")
        b.cooldown(minutes: 8)
        return Workout(id: "threshold-2x20", name: "Tröskel 2×20", summary: "Två långa block på tröskeln. Tufft men det höjer din FTP.", category: .threshold, steps: b.steps)
    }()

    public static let vo2max5x3: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 12)
        b.steady(seconds: 30, at: 1.1, label: "Väck benen")
        b.recover(seconds: 150)
        b.intervals(5, on: 180, at: 1.18, off: 180, at: 0.5, cadence: 100, label: "VO2max")
        b.cooldown(minutes: 8)
        return Workout(id: "vo2-5x3", name: "VO2max 5×3", summary: "Fem hårda tremunutersintervaller. Höjer taket för din syreupptagning.", category: .vo2max, steps: b.steps)
    }()

    public static let microBursts: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 10)
        for set in 1...2 {
            b.intervals(10, on: 30, at: 1.3, off: 30, at: 0.55, label: "Burst set \(set)", recoverAfterLast: false)
            b.recover(seconds: 300)
        }
        b.cooldown(minutes: 6)
        return Workout(id: "bursts-30-30", name: "30/30 bursts", summary: "Två set med 10 × 30 sekunder hårt / 30 sekunder lätt.", category: .vo2max, steps: b.steps)
    }()

    public static let sprints: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 12)
        b.intervals(8, on: 15, at: 1.8, off: 165, at: 0.5, label: "Sprint")
        b.cooldown(minutes: 8)
        return Workout(id: "sprints-8x15", name: "Sprintträning", summary: "Åtta maximala 15-sekunderssprinter med full vila. Stå upp och ös!", category: .sprint, steps: b.steps)
    }()

    public static let pyramid: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 10)
        for (sec, f) in [(60.0, 1.05), (120, 1.0), (180, 0.95), (240, 0.92), (180, 0.95), (120, 1.0), (60, 1.05)] {
            b.steady(seconds: sec, at: f, label: "Pyramid")
            b.recover(seconds: sec / 2)
        }
        b.cooldown(minutes: 8)
        return Workout(id: "pyramid", name: "Pyramiden", summary: "Upp och ner för pyramiden: 1–2–3–4–3–2–1 minuter runt tröskeln.", category: .threshold, steps: b.steps)
    }()

    /// Ramp test: +20 W every minute until you can't hold it. FTP = 75 % of best minute.
    public static let rampTest: Workout = {
        var b = WorkoutBuilder()
        b.append(WorkoutStep(kind: .warmup, duration: 300, start: .watts(100), end: .watts(120), label: "Uppvärmning"))
        var w = 120.0
        var k = 1
        while w <= 600 {
            b.append(WorkoutStep(kind: .work, duration: 60, start: .watts(w), label: "Steg \(k)"))
            w += 20
            k += 1
        }
        return Workout(
            id: "ftp-ramp", name: "FTP-ramptest",
            summary: "Effekten ökar 20 W varje minut tills du inte orkar mer. Tryck \"Avsluta\" när du är slut. Din FTP blir 75 % av din bästa minut.",
            category: .test, steps: b.steps, test: .ramp)
    }()

    /// Classic 20-minute test. FTP = 95 % of the 20-minute average.
    public static let twentyMinuteTest: Workout = {
        var b = WorkoutBuilder()
        b.warmup(minutes: 10)
        b.intervals(3, on: 60, at: 1.0, off: 60, at: 0.55, label: "Öppnare")
        b.steady(minutes: 5, at: 1.05, label: "Rensa benen")
        b.recover(seconds: 600)
        b.free(minutes: 20, label: "20 minuter för fullt – håll jämnt!")
        b.cooldown(minutes: 10)
        return Workout(
            id: "ftp-20", name: "20-minuterstest",
            summary: "Det klassiska FTP-testet. Ett jämnt maxförsök i 20 minuter utan ERG. FTP blir 95 % av snittet.",
            category: .test, steps: b.steps, test: .twentyMinute)
    }()
}

/// Imports the common plain-text `.erg` (watts) and `.mrc` (% of FTP) formats.
public enum WorkoutFileParser {
    public enum ParseError: Error, Equatable {
        case missingData
        case unknownUnits
        case badLine(String)
    }

    public static func parse(text: String, fallbackName: String) throws -> Workout {
        var name = fallbackName
        var inData = false
        var percent: Bool?
        var points: [(t: Double, v: Double)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            let upper = line.uppercased()
            if upper.hasPrefix("[COURSE DATA]") { inData = true; continue }
            if upper.hasPrefix("[END COURSE DATA]") { inData = false; continue }
            if upper.hasPrefix("[") { continue }
            if !inData {
                if upper.hasPrefix("DESCRIPTION"), let eq = line.firstIndex(of: "=") {
                    let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { name = v }
                } else if upper.contains("MINUTES") && upper.contains("PERCENT") {
                    percent = true
                } else if upper.contains("MINUTES") && upper.contains("WATTS") {
                    percent = false
                }
                continue
            }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).compactMap { Double($0) }
            guard parts.count >= 2 else { throw ParseError.badLine(line) }
            points.append((parts[0] * 60, parts[1]))
        }
        guard points.count >= 2 else { throw ParseError.missingData }
        guard let isPercent = percent else { throw ParseError.unknownUnits }
        var steps: [WorkoutStep] = []
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dt = b.t - a.t
            guard dt > 0.5 else { continue } // vertical edge = step change
            let s: PowerTarget = isPercent ? .ftp(a.v / 100) : .watts(a.v)
            let e: PowerTarget = isPercent ? .ftp(b.v / 100) : .watts(b.v)
            let kind: WorkoutStep.Kind = a.v == b.v ? .steady : .ramp
            steps.append(WorkoutStep(kind: kind, duration: dt, start: s, end: e, label: kind == .ramp ? "Ramp" : "Jämnt"))
        }
        guard !steps.isEmpty else { throw ParseError.missingData }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a: stable across launches
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
        return Workout(id: "import-\(String(hash, radix: 16))", name: name, summary: "Importerat pass", category: .custom, steps: steps)
    }
}

extension WorkoutFileParser {
    /// Writes a workout as .mrc (minutes, % of FTP) so it can be shared or used in other apps.
    public static func mrc(_ w: Workout, ftp: Double) -> String {
        var lines = [
            "[COURSE HEADER]", "VERSION = 2", "UNITS = ENGLISH", "DESCRIPTION = \(w.name)",
            "FILE NAME = \(w.name)", "MINUTES PERCENT", "[END COURSE HEADER]", "[COURSE DATA]",
        ]
        var t = 0.0
        func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
        for s in w.steps {
            let a = (s.isFree ? 1 : s.start.fraction(ftp: ftp)) * 100
            let b = (s.isFree ? 1 : s.end.fraction(ftp: ftp)) * 100
            lines.append("\(fmt(t / 60))\t\(fmt(a))")
            t += s.duration
            lines.append("\(fmt(t / 60))\t\(fmt(b))")
        }
        lines.append("[END COURSE DATA]")
        return lines.joined(separator: "\n") + "\n"
    }
}
