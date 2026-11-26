import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct WorkoutTests {
    @Test func libraryIsSane() {
        #expect(Set(WorkoutLibrary.all.map(\.id)).count == WorkoutLibrary.all.count, "unique ids")
        for w in WorkoutLibrary.all {
            #expect(w.duration > 10 * 60, "\(w.name) too short")
            #expect(w.steps.allSatisfy { $0.duration > 0 })
            let tss = w.estimatedTSS(ftp: 250)
            #expect(tss > 10 && tss < 200, "\(w.name) TSS \(tss)")
        }
    }

    @Test func positionAndTargets() throws {
        let w = WorkoutLibrary.sweetSpot3x10
        #expect(w.position(at: 0)?.index == 0)
        // warm-up ramps 45 % → 70 %
        #expect(abs((w.targetWatts(at: 0, ftp: 200) ?? 0) - 90) < 0.01)
        #expect(abs((w.targetWatts(at: 300, ftp: 200) ?? 0) - 115) < 0.01)
        #expect(w.position(at: w.duration) == nil)
        #expect(w.targetWatts(at: w.duration + 1, ftp: 200) == nil)
        let idx = try #require(w.steps.firstIndex { $0.label.hasPrefix("Sweet spot 1") })
        #expect(w.position(at: w.startTime(ofStep: idx) + 1)?.index == idx)
    }

    @Test func freeStepsHaveNoTarget() throws {
        let w = WorkoutLibrary.twentyMinuteTest
        let idx = try #require(w.steps.firstIndex { $0.isFree })
        #expect(w.targetWatts(at: w.startTime(ofStep: idx) + 5, ftp: 250) == nil)
    }

    @Test func steadyTSSMatchesDefinition() {
        let w = Workout(id: "t", name: "t", summary: "", category: .custom,
                        steps: [WorkoutStep(kind: .work, duration: 3600, start: .ftp(1.0), label: "")])
        #expect(abs(w.estimatedTSS(ftp: 250) - 100) < 1e-9)
    }

    @Test func parsesMrcAndErg() throws {
        let mrc = """
        [COURSE HEADER]
        VERSION = 2
        UNITS = ENGLISH
        DESCRIPTION = Mitt pass
        MINUTES PERCENT
        [END COURSE HEADER]
        [COURSE DATA]
        0.00\t50
        10.00\t75
        10.00\t100
        15.00\t100
        [END COURSE DATA]
        """
        let w = try WorkoutFileParser.parse(text: mrc, fallbackName: "x")
        #expect(w.name == "Mitt pass")
        #expect(w.steps.count == 2)
        #expect(w.duration == 15 * 60)
        #expect(w.steps[0].kind == .ramp && w.steps[0].end == .ftp(0.75))
        #expect(w.steps[1].start == .ftp(1.0))
        // stable id across parses
        #expect(try WorkoutFileParser.parse(text: mrc, fallbackName: "x").id == w.id)

        let erg = "[COURSE HEADER]\nMINUTES WATTS\n[END COURSE HEADER]\n[COURSE DATA]\n0 150\n5 150\n5 250\n6 250\n[END COURSE DATA]"
        let e = try WorkoutFileParser.parse(text: erg, fallbackName: "Fil")
        #expect(e.name == "Fil" && e.steps.count == 2 && e.steps[1].start == .watts(250))
        #expect(throws: WorkoutFileParser.ParseError.self) { try WorkoutFileParser.parse(text: "nonsense", fallbackName: "x") }
    }
}

@Suite struct StatsTests {
    func samples(_ powers: [Int]) -> [RideSample] {
        powers.enumerated().map { i, p in
            RideSample(t: i, power: p, heartRate: 140, cadence: p > 0 ? 90 : 0, speed: 10, distance: Double(i) * 10, elevation: 0, grade: 0)
        }
    }

    @Test func steadyRideStats() {
        let s = RideStats.compute(samples: samples(Array(repeating: 200, count: 3600)), ftp: 200)
        #expect(abs(s.normalizedPower - 200) < 1e-6)
        #expect(abs(s.intensityFactor - 1) < 1e-9)
        #expect(abs(s.tss - 100) < 0.1)
        #expect(abs(s.kilojoules - 720) < 1e-6)
        #expect(s.averageHeartRate == 140 && s.averageCadence == 90)
        #expect(s.timeInZones[3] == 3600)
        #expect(s.bestEfforts.map(\.seconds) == [5, 60, 300, 1200])
    }

    @Test func normalizedPowerPunishesVariability() {
        let variable = (0..<3600).map { ($0 / 30) % 2 == 0 ? 300 : 100 }
        let s = RideStats.compute(samples: samples(variable), ftp: 250)
        #expect(abs(s.averagePower - 200) < 1)
        #expect(s.normalizedPower > 220)
    }

    @Test func ftpEstimates() {
        // ramp: best minute 400 W → 300 W
        let ramp = Array(repeating: 150, count: 600) + Array(repeating: 400, count: 60) + Array(repeating: 100, count: 60)
        #expect(RideStats.ftpEstimate(test: .ramp, samples: samples(ramp)) == 300)
        let twenty = Array(repeating: 100, count: 300) + Array(repeating: 260, count: 1200)
        #expect(RideStats.ftpEstimate(test: .twentyMinute, samples: samples(twenty)) == 247)
    }
}

@Suite struct EngineTests {
    let route = RouteBuilder.build(RouteLibrary.sjorundan)

    @Test func rideAlongRecordsOneSamplePerSecond() {
        let e = RideEngine(config: .init(route: route, rider: RiderProfile(weightKg: 75, ftp: 250)))
        for _ in 0..<(60 * 60) { e.tick(dt: 1.0 / 60, inputs: RideInputs(power: 200, cadence: 90, heartRate: 130)) }
        #expect(e.samples.count == 60 || e.samples.count == 61)
        #expect(e.distance > 300 && e.distance < 700)
        #expect(e.speed > 6)
        #expect(abs(e.power3s - 200) < 1e-6)
        #expect(e.trainerTarget != .none)
        let rec = e.finish(startDate: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(rec.stats.duration == e.samples.count)
        #expect(abs(rec.stats.averagePower - 200) < 5)
    }

    @Test func autoPauseStopsTheClock() {
        let e = RideEngine(config: .init(route: route, rider: .default))
        for _ in 0..<600 { e.tick(dt: 0.1, inputs: RideInputs(power: 0)) }
        #expect(e.isAutoPaused)
        #expect(e.timerTime < 3.5)
        #expect(e.samples.count <= 4)
        e.isPaused = true
        e.tick(dt: 0.1, inputs: RideInputs(power: 300))
        #expect(e.distance == 0, "manual pause freezes everything")
    }

    @Test func ergTargetsFollowWorkoutAndIntensity() {
        let w = WorkoutLibrary.vo2max5x3
        let e = RideEngine(config: .init(route: route, rider: RiderProfile(ftp: 200), mode: .workout(w)))
        e.tick(dt: 0.1, inputs: RideInputs(power: 150))
        #expect(e.trainerTarget == .erg(watts: 90)) // 45 % of 200
        e.workoutIntensity = 1.1
        #expect(e.trainerTarget == .erg(watts: 99))
        e.setErgEnabled(false)
        if case .simulation = e.trainerTarget {} else { Issue.record("expected simulation when ERG off") }
        e.setErgEnabled(true)
        e.skipWorkoutStep()
        e.tick(dt: 0.1, inputs: RideInputs(power: 150))
        #expect(e.workoutStatus?.stepIndex == 1)
        let events = e.drainEvents()
        #expect(events.contains { if case .workoutStep(1, _) = $0 { return true }; return false })
    }

    @Test func trainerDifficultyScalesGradeOnly() {
        let hilly = RouteBuilder.build(RouteLibrary.fjallvagen)
        let climb = hilly.segments.first { $0.kind == .climb }!
        let e = RideEngine(config: .init(route: hilly, rider: .default, trainerDifficulty: 0.5))
        // ride to the middle of the climb
        while e.distance < (climb.startDistance + climb.endDistance) / 2 {
            e.tick(dt: 0.25, inputs: RideInputs(power: 400))
        }
        guard case .simulation(let g, _, _) = e.trainerTarget else { Issue.record("no sim"); return }
        #expect(abs(g - e.grade * 50) < 1e-9)
        #expect(e.grade > 0.03)
    }

    @Test func segmentsLapsAndPersonalBests() {
        let short = RouteBuilder.build(RouteLibrary.skogsslingan)
        let e = RideEngine(config: .init(route: short, rider: RiderProfile(weightKg: 70, ftp: 300), personalBests: [:]))
        var events: [RideEvent] = []
        var guardCount = 0
        while e.lapCount < 1 && guardCount < 200_000 {
            e.tick(dt: 0.25, inputs: RideInputs(power: 300))
            events += e.drainEvents()
            guardCount += 1
        }
        #expect(e.lapCount == 1)
        let finished = events.compactMap { if case .segmentFinished(let r) = $0 { return r }; return nil }
        #expect(finished.count == short.segments.count)
        #expect(finished.allSatisfy { $0.isPersonalBest && $0.seconds > 10 && abs($0.averagePower - 300) < 1 })
        #expect(events.contains { if case .lapCompleted(1, _) = $0 { return true }; return false })
        #expect(events.contains(.kilometer(1)))
        // second lap slower → no PR
        let pbs = e.personalBests
        let e2 = RideEngine(config: .init(route: short, rider: RiderProfile(weightKg: 70, ftp: 300), personalBests: pbs))
        var ev2: [RideEvent] = []
        while e2.lapCount < 1 { e2.tick(dt: 0.25, inputs: RideInputs(power: 200)); ev2 += e2.drainEvents() }
        let f2 = ev2.compactMap { if case .segmentFinished(let r) = $0 { return r }; return nil }
        #expect(f2.allSatisfy { !$0.isPersonalBest })
    }

    @Test func botsRideAndDraftHelps() {
        let bots = BotProfile.group(wattsPerKg: 3.0, count: 6, seed: 1)
        let e = RideEngine(config: .init(route: route, rider: RiderProfile(weightKg: 75), bots: bots))
        for _ in 0..<(120 * 10) { e.tick(dt: 0.1, inputs: RideInputs(power: 225)) }
        #expect(e.bots.allSatisfy { $0.distance > 500 && $0.speed > 7 })
        #expect(e.bots.allSatisfy { abs($0.lateral) <= 2.8 })
        let board = e.leaderboard()
        #expect(board.count == 7 && board.filter(\.isPlayer).count == 1)
        #expect(zip(board, board.dropFirst()).allSatisfy { $0.gapMeters >= $1.gapMeters })
    }

    @Test func rampTestProducesFTPEstimate() {
        let e = RideEngine(config: .init(route: route, rider: RiderProfile(ftp: 200), mode: .workout(WorkoutLibrary.rampTest)))
        // follow the ERG target perfectly for 15 minutes
        for _ in 0..<(15 * 60 * 4) {
            let target: Double
            if case .erg(let w) = e.trainerTarget { target = Double(w) } else { target = 100 }
            e.tick(dt: 0.25, inputs: RideInputs(power: target))
        }
        let rec = e.finish(startDate: Date())
        // after 15 min: warmup 5 + 10 steps → last full minute at 300 W → 225
        #expect(rec.ftpEstimate.map { abs($0 - 225) <= 15 } == true, "\(String(describing: rec.ftpEstimate))")
    }
}

@Suite struct FITTests {
    @Test func crcMatchesReference() {
        // CRC-16/ARC check value
        #expect(FITEncoder.crc16(Array("123456789".utf8)) == 0xBB3D)
    }

    @Test func encodesValidFile() throws {
        let route = RouteBuilder.build(RouteLibrary.skogsslingan)
        let e = RideEngine(config: .init(route: route, rider: RiderProfile(ftp: 250)))
        for _ in 0..<(300 * 4) { e.tick(dt: 0.25, inputs: RideInputs(power: 220, cadence: 88, heartRate: 142)) }
        let rec = e.finish(startDate: Date(timeIntervalSince1970: 1_750_000_000))
        let data = FITEncoder.encode(rec)
        let bytes = [UInt8](data)

        // header
        #expect(bytes[0] == 14)
        #expect(Array(bytes[8..<12]) == Array(".FIT".utf8))
        let dataSize = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        #expect(dataSize == bytes.count - 14 - 2)
        #expect(FITEncoder.crc16(Array(bytes[0..<12])) == UInt16(bytes[12]) | UInt16(bytes[13]) << 8)
        // whole-file CRC including trailing CRC bytes is zero
        #expect(FITEncoder.crc16(bytes) == 0)

        // decode records with a minimal reader
        let decoded = try MiniFITReader.decode(bytes)
        let records = decoded.filter { $0.global == 20 }
        #expect(records.count == rec.samples.count)
        let first = try #require(records.first)
        #expect(first.fields[7] == 220) // power
        #expect(first.fields[3] == 142) // hr
        #expect(first.fields[4] == 88)  // cadence
        #expect(first.fields[253] == UInt64(FITEncoder.fitTimestamp(rec.startDate)))
        let session = try #require(decoded.first { $0.global == 18 })
        #expect(session.fields[5] == 2 && session.fields[6] == 58)
        #expect(session.fields[20] == UInt64(rec.stats.averagePower.rounded()))
        #expect(decoded.first?.global == 0, "file_id first")
        #expect(decoded.last?.global == 34, "activity last")
    }
}

/// Independent, minimal FIT reader used only to verify the encoder.
enum MiniFITReader {
    struct Msg {
        var global: UInt16
        var fields: [UInt8: UInt64]
    }
    struct Err: Error {}

    static func decode(_ b: [UInt8]) throws -> [Msg] {
        let headerSize = Int(b[0])
        let end = b.count - 2
        var i = headerSize
        var defs: [UInt8: (UInt16, [(UInt8, Int)])] = [:]
        var out: [Msg] = []
        while i < end {
            let h = b[i]; i += 1
            guard h & 0x80 == 0 else { throw Err() } // no compressed timestamps
            let local = h & 0x0F
            if h & 0x40 != 0 {
                i += 1 // reserved
                guard b[i] == 0 else { throw Err() }
                i += 1
                let global = UInt16(b[i]) | UInt16(b[i + 1]) << 8; i += 2
                let n = Int(b[i]); i += 1
                var fields: [(UInt8, Int)] = []
                for _ in 0..<n { fields.append((b[i], Int(b[i + 1]))); i += 3 }
                defs[local] = (global, fields)
            } else {
                guard let (global, fields) = defs[local] else { throw Err() }
                var values: [UInt8: UInt64] = [:]
                for (num, size) in fields {
                    var v: UInt64 = 0
                    for k in 0..<size { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
                    values[num] = v
                    i += size
                }
                out.append(Msg(global: global, fields: values))
            }
        }
        guard i == end else { throw Err() }
        return out
    }
}
