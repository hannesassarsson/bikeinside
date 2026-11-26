import Testing
@testable import BikeinsideCore

@Suite struct BLEParsingTests {
    @Test func indoorBikeDataTypicalTrainer() throws {
        // flags 0x0044: speed present (bit0 = 0), cadence (bit2), power (bit6)
        // speed 32.50 km/h = 3250 = 0x0CB2, cadence 90 rpm = 180 = 0x00B4, power 250 W = 0x00FA
        let d = try #require(IndoorBikeData.parse([0x44, 0x00, 0xB2, 0x0C, 0xB4, 0x00, 0xFA, 0x00]))
        #expect(d.speedKmh == 32.5)
        #expect(d.cadenceRpm == 90)
        #expect(d.powerW == 250)
        #expect(d.heartRateBpm == nil)
    }

    @Test func indoorBikeDataAllFields() throws {
        // bits 1..12 set except 0 → speed present too; build packet field by field
        let flags: UInt16 = 0b1_1111_1111_1110
        var b: [UInt8] = [UInt8(flags & 0xFF), UInt8(flags >> 8)]
        b += [0x10, 0x27] // speed 100.00
        b += [0x88, 0x13] // avg speed 50.00
        b += [0xC8, 0x00] // cadence 100
        b += [0xB4, 0x00] // avg cadence 90
        b += [0x10, 0x27, 0x00] // distance 10000 m
        b += [0x05, 0x00] // resistance 5
        b += [0x2C, 0x01] // power 300
        b += [0xC8, 0x00] // avg power 200
        b += [0x64, 0x00, 0x00, 0x00, 0x00] // energy 100 kcal, per h, per min
        b += [0x96] // hr 150
        b += [0x0A] // MET
        b += [0x3C, 0x00] // elapsed 60
        b += [0x1E, 0x00] // remaining 30
        let d = try #require(IndoorBikeData.parse(b))
        #expect(d.speedKmh == 100 && d.averageSpeedKmh == 50)
        #expect(d.cadenceRpm == 100 && d.averageCadenceRpm == 90)
        #expect(d.totalDistanceM == 10000 && d.resistanceLevel == 5)
        #expect(d.powerW == 300 && d.averagePowerW == 200)
        #expect(d.totalEnergyKcal == 100 && d.heartRateBpm == 150)
        #expect(d.elapsedTimeS == 60 && d.remainingTimeS == 30)
    }

    @Test func indoorBikeDataMoreDataPacketHasNoSpeed() throws {
        // bit0 = 1 → speed absent; only power follows
        let d = try #require(IndoorBikeData.parse([0x41, 0x00, 0x96, 0x00]))
        #expect(d.speedKmh == nil && d.powerW == 150)
    }

    @Test func truncatedPacketsAreRejected() {
        #expect(IndoorBikeData.parse([0x44, 0x00, 0xB2]) == nil)
        #expect(IndoorBikeData.parse([]) == nil)
        #expect(CyclingPowerMeasurement.parse([0x20, 0x00, 0x10]) == nil)
        #expect(HeartRateMeasurement.parse([0x01, 0x50]) == nil)
    }

    @Test func negativePowerIsSigned() throws {
        let d = try #require(IndoorBikeData.parse([0x41, 0x00, 0xFF, 0xFF]))
        #expect(d.powerW == -1)
    }

    @Test func cyclingPowerWithCrankData() throws {
        // flags 0x0020 (crank present), power 0x00F0 = 240, revs 0x0102 = 258, time 0x0400 = 1024
        let m = try #require(CyclingPowerMeasurement.parse([0x20, 0x00, 0xF0, 0x00, 0x02, 0x01, 0x00, 0x04]))
        #expect(m.powerW == 240)
        #expect(m.cumulativeCrankRevs == 258)
        #expect(m.lastCrankEventTime == 1024)
        #expect(m.cumulativeWheelRevs == nil)
    }

    @Test func cyclingPowerWithBalanceTorqueWheelCrank() throws {
        // flags: balance(0) + torque(2) + wheel(4) + crank(5) = 0x35
        let b: [UInt8] = [0x35, 0x00, 0x2C, 0x01, 0x64, 0x00, 0x01, 0x10, 0x00, 0x00, 0x00, 0x00, 0x08, 0x05, 0x00, 0x00, 0x02]
        let m = try #require(CyclingPowerMeasurement.parse(b))
        #expect(m.powerW == 300)
        #expect(m.pedalBalancePercent == 50)
        #expect(m.cumulativeWheelRevs == 16)
        #expect(m.lastWheelEventTime == 0x0800)
        #expect(m.cumulativeCrankRevs == 5)
        #expect(m.lastCrankEventTime == 0x0200)
    }

    @Test func heartRateFormats() throws {
        let a = try #require(HeartRateMeasurement.parse([0x00, 0x48]))
        #expect(a.bpm == 72 && a.sensorContact == nil)
        let b = try #require(HeartRateMeasurement.parse([0x01, 0x2C, 0x01]))
        #expect(b.bpm == 300)
        // contact supported+detected, RR intervals 1024 → 1.0 s and 512 → 0.5 s
        let c = try #require(HeartRateMeasurement.parse([0x16, 0x50, 0x00, 0x04, 0x00, 0x02]))
        #expect(c.bpm == 80 && c.sensorContact == true && c.rrIntervals == [1.0, 0.5])
        let d = try #require(HeartRateMeasurement.parse([0x04, 0x50]))
        #expect(d.sensorContact == false)
    }

    @Test func cscMeasurement() throws {
        let m = try #require(CSCMeasurement.parse([0x02, 0x0A, 0x00, 0x00, 0x08]))
        #expect(m.cumulativeCrankRevs == 10 && m.lastCrankEventTime == 2048 && m.cumulativeWheelRevs == nil)
    }

    @Test func controlPointEncoding() {
        #expect(FTMSCommand.requestControl.bytes == [0x00])
        #expect(FTMSCommand.startOrResume.bytes == [0x07])
        #expect(FTMSCommand.stop.bytes == [0x08, 0x01])
        #expect(FTMSCommand.pause.bytes == [0x08, 0x02])
        #expect(FTMSCommand.setTargetPower(watts: 250).bytes == [0x05, 0xFA, 0x00])
        // grade -1.5 % → -150 = 0xFF6A; wind 0; crr 0.004 → 40; cw 0.51 → 51
        #expect(FTMSCommand.setSimulation(gradePercent: -1.5, windSpeed: 0, crr: 0.004, windResistance: 0.51).bytes
            == [0x11, 0x00, 0x00, 0x6A, 0xFF, 40, 51])
        // saturation instead of overflow
        #expect(FTMSCommand.setTargetPower(watts: 100_000).bytes == [0x05, 0xFF, 0x7F])
    }

    @Test func controlResponseAndFeatures() throws {
        let r = try #require(FTMSControlResponse.parse([0x80, 0x05, 0x01]))
        #expect(r.requestOpcode == 0x05 && r.result == .success)
        #expect(FTMSControlResponse.parse([0x05, 0x01]) == nil)
        // features: cadence(1) + power(14); targets: power(3) + sim(13)
        let f = try #require(FitnessMachineFeatures.parse([0x02, 0x40, 0, 0, 0x08, 0x20, 0, 0]))
        #expect(f.supportsCadence && f.supportsPowerMeasurement && !f.supportsHeartRate)
        #expect(f.supportsPowerTarget && f.supportsSimulation && !f.supportsResistanceTarget)
        let pr = try #require(SupportedPowerRange.parse([0x00, 0x00, 0xD0, 0x07, 0x01, 0x00]))
        #expect(pr.maxW == 2000 && pr.clamp(2500) == 2000)
    }
}

@Suite struct CadenceTests {
    @Test func cadenceFromCrankEvents() {
        var c = CrankCadenceCalculator()
        c.update(revs: 100, eventTime: 0, now: 0)
        // 1.5 revs/s worth: 3 revs in 2 s (2048 ticks) → 90 rpm
        let rpm = c.update(revs: 103, eventTime: 2048, now: 2)
        #expect(rpm.map { abs($0 - 90) < 0.01 } == true)
    }

    @Test func cadenceHandlesWraparound() {
        var c = CrankCadenceCalculator()
        c.update(revs: 65535, eventTime: 65024, now: 0)
        let rpm = c.update(revs: 1, eventTime: 512, now: 1) // 2 revs, 1024 ticks → 120 rpm
        #expect(rpm.map { abs($0 - 120) < 0.01 } == true)
    }

    @Test func cadenceDropsToZeroWhenPedallingStops() {
        var c = CrankCadenceCalculator()
        c.update(revs: 1, eventTime: 0, now: 0)
        c.update(revs: 2, eventTime: 700, now: 0.7)
        #expect((c.cadence ?? 0) > 0)
        c.update(revs: 2, eventTime: 700, now: 2.0)
        #expect((c.cadence ?? 0) > 0)
        c.update(revs: 2, eventTime: 700, now: 4.0)
        #expect(c.cadence == 0)
        var d = CrankCadenceCalculator()
        d.update(revs: 1, eventTime: 0, now: 0)
        d.update(revs: 2, eventTime: 700, now: 0.7)
        d.tick(now: 10)
        #expect(d.cadence == 0)
    }
}

@Suite struct FusionTests {
    @Test func powerMeterBeatsTrainerUntilStale() {
        var hub = SensorHub()
        hub.ingest(role: .trainer, power: 200, cadence: 85, heartRate: 120, now: 0)
        hub.ingest(role: .powerMeter, power: 210, now: 0)
        hub.ingest(role: .heartRate, heartRate: 130, now: 0)
        var i = hub.inputs(now: 1)
        #expect(i.power == 210 && i.cadence == 85 && i.heartRate == 130)
        #expect(hub.powerSource(now: 1) == .powerMeter)
        hub.ingest(role: .trainer, power: 205, now: 4)
        i = hub.inputs(now: 4)
        #expect(i.power == 205, "falls back to trainer when power meter is stale")
        #expect(i.heartRate == nil, "stale HR dropped")
    }

    @Test func rejectsGarbage() {
        var hub = SensorHub()
        hub.ingest(role: .trainer, power: -5, cadence: .nan, heartRate: 0, now: 0)
        #expect(hub.inputs(now: 0) == RideInputs())
    }
}

@Suite struct TrainerControlTests {
    @Test func fullHandshakeThenCoalescedSetpoints() {
        var s = TrainerControlState()
        s.connect()
        s.setTarget(.simulation(gradePercent: 2, crr: 0.004, windResistance: 0.51))
        #expect(s.nextCommand(now: 0) == .requestControl)
        #expect(s.nextCommand(now: 0.1) == nil, "one command in flight")
        s.handle(FTMSControlResponse(requestOpcode: 0x00, result: .success), now: 0.2)
        #expect(s.nextCommand(now: 0.2) == .startOrResume)
        s.handle(FTMSControlResponse(requestOpcode: 0x07, result: .notSupported), now: 0.3)
        #expect(s.phase == .ready)
        #expect(s.nextCommand(now: 0.3) == .setSimulation(gradePercent: 2, windSpeed: 0, crr: 0.004, windResistance: 0.51))
        s.handle(FTMSControlResponse(requestOpcode: 0x11, result: .success), now: 0.35)
        // several updates within the rate limit → only the newest goes out
        s.setTarget(.simulation(gradePercent: 2.5, crr: 0.004, windResistance: 0.51))
        s.setTarget(.simulation(gradePercent: 3.0, crr: 0.004, windResistance: 0.51))
        #expect(s.nextCommand(now: 0.5) == nil, "rate limited")
        #expect(s.nextCommand(now: 0.9) == .setSimulation(gradePercent: 3.0, windSpeed: 0, crr: 0.004, windResistance: 0.51))
        s.handle(FTMSControlResponse(requestOpcode: 0x11, result: .success), now: 1.0)
        // tiny change is ignored
        s.setTarget(.simulation(gradePercent: 3.05, crr: 0.004, windResistance: 0.51))
        #expect(s.nextCommand(now: 2) == nil)
        // but refreshed eventually
        #expect(s.nextCommand(now: 10) != nil)
    }

    @Test func switchingToErgSendsPower() {
        var s = readyState()
        s.setTarget(.erg(watts: 220))
        #expect(s.nextCommand(now: 5) == .setTargetPower(watts: 220))
    }

    @Test func recoversFromLostControlAndTimeouts() {
        var s = readyState()
        s.setTarget(.erg(watts: 200))
        _ = s.nextCommand(now: 5)
        s.handle(FTMSControlResponse(requestOpcode: 0x05, result: .controlNotPermitted), now: 5.1)
        #expect(s.phase == .requestingControl)
        #expect(s.nextCommand(now: 5.2) == nil, "backs off")
        #expect(s.nextCommand(now: 6.2) == .requestControl)
        // no response → timeout → retry
        #expect(s.nextCommand(now: 7) == nil)
        #expect(s.nextCommand(now: 9.5) == nil, "timed out, backing off")
        #expect(s.nextCommand(now: 10.6) == .requestControl)
    }

    private func readyState() -> TrainerControlState {
        var s = TrainerControlState()
        s.connect()
        _ = s.nextCommand(now: 0)
        s.handle(FTMSControlResponse(requestOpcode: 0x00, result: .success), now: 0)
        _ = s.nextCommand(now: 0)
        s.handle(FTMSControlResponse(requestOpcode: 0x07, result: .success), now: 0)
        return s
    }
}
