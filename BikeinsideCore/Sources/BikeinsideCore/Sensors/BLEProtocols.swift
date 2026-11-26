import Foundation

// Bluetooth SIG GATT definitions used by Bikeinside. Parsing lives here (pure
// functions on bytes, fully unit-tested); CoreBluetooth plumbing lives in the app.

public enum GATT {
    // Services (16-bit UUIDs)
    public static let fitnessMachineService: UInt16 = 0x1826
    public static let cyclingPowerService: UInt16 = 0x1818
    public static let heartRateService: UInt16 = 0x180D
    public static let cyclingSpeedCadenceService: UInt16 = 0x1816
    public static let batteryService: UInt16 = 0x180F
    public static let deviceInformationService: UInt16 = 0x180A

    // Characteristics
    public static let fitnessMachineFeature: UInt16 = 0x2ACC
    public static let indoorBikeData: UInt16 = 0x2AD2
    public static let trainingStatus: UInt16 = 0x2AD3
    public static let supportedResistanceLevelRange: UInt16 = 0x2AD6
    public static let supportedPowerRange: UInt16 = 0x2AD8
    public static let fitnessMachineControlPoint: UInt16 = 0x2AD9
    public static let fitnessMachineStatus: UInt16 = 0x2ADA
    public static let cyclingPowerMeasurement: UInt16 = 0x2A63
    public static let cyclingPowerFeature: UInt16 = 0x2A65
    public static let heartRateMeasurement: UInt16 = 0x2A37
    public static let cscMeasurement: UInt16 = 0x2A5B
    public static let batteryLevel: UInt16 = 0x2A19
    public static let manufacturerName: UInt16 = 0x2A29
    public static let modelNumber: UInt16 = 0x2A24
}

/// Little-endian cursor over a BLE payload. Every read is bounds-checked and
/// returns nil when the packet is truncated, so malformed packets can't crash us.
public struct ByteReader {
    public let bytes: [UInt8]
    public private(set) var offset = 0

    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public init(_ data: Data) { self.bytes = [UInt8](data) }

    public var remaining: Int { bytes.count - offset }

    public mutating func u8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    public mutating func u16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    public mutating func s16() -> Int16? { u16().map { Int16(bitPattern: $0) } }

    public mutating func u24() -> UInt32? {
        guard remaining >= 3 else { return nil }
        defer { offset += 3 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
    }

    public mutating func u32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    public mutating func skip(_ n: Int) -> Bool {
        guard remaining >= n else { return false }
        offset += n
        return true
    }
}

// MARK: - Fitness Machine Service (smart trainers)

/// Decoded Indoor Bike Data (0x2AD2). Fields absent from the packet are nil.
public struct IndoorBikeData: Equatable, Sendable {
    public var speedKmh: Double?
    public var averageSpeedKmh: Double?
    public var cadenceRpm: Double?
    public var averageCadenceRpm: Double?
    public var totalDistanceM: Int?
    public var resistanceLevel: Int?
    public var powerW: Int?
    public var averagePowerW: Int?
    public var totalEnergyKcal: Int?
    public var heartRateBpm: Int?
    public var elapsedTimeS: Int?
    public var remainingTimeS: Int?

    public init() {}

    public static func parse(_ bytes: [UInt8]) -> IndoorBikeData? {
        var r = ByteReader(bytes)
        guard let flags = r.u16() else { return nil }
        var d = IndoorBikeData()
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }
        // Bit 0 "More Data" is inverted: 0 means Instantaneous Speed IS present.
        if !has(0) {
            guard let v = r.u16() else { return nil }
            d.speedKmh = Double(v) / 100
        }
        if has(1) { guard let v = r.u16() else { return nil }; d.averageSpeedKmh = Double(v) / 100 }
        if has(2) { guard let v = r.u16() else { return nil }; d.cadenceRpm = Double(v) / 2 }
        if has(3) { guard let v = r.u16() else { return nil }; d.averageCadenceRpm = Double(v) / 2 }
        if has(4) { guard let v = r.u24() else { return nil }; d.totalDistanceM = Int(v) }
        if has(5) { guard let v = r.s16() else { return nil }; d.resistanceLevel = Int(v) }
        if has(6) { guard let v = r.s16() else { return nil }; d.powerW = Int(v) }
        if has(7) { guard let v = r.s16() else { return nil }; d.averagePowerW = Int(v) }
        if has(8) {
            guard let total = r.u16(), r.skip(3) else { return nil } // + per hour (u16) + per minute (u8)
            d.totalEnergyKcal = total == 0xFFFF ? nil : Int(total)
        }
        if has(9) { guard let v = r.u8() else { return nil }; d.heartRateBpm = v == 0 ? nil : Int(v) }
        if has(10) { guard r.skip(1) else { return nil } } // metabolic equivalent
        if has(11) { guard let v = r.u16() else { return nil }; d.elapsedTimeS = Int(v) }
        if has(12) { guard let v = r.u16() else { return nil }; d.remainingTimeS = Int(v) }
        return d
    }
}

/// Fitness Machine Feature (0x2ACC): what the trainer can measure and control.
public struct FitnessMachineFeatures: Equatable, Sendable {
    public var raw: UInt32
    public var targetRaw: UInt32

    public init(raw: UInt32, targetRaw: UInt32) {
        self.raw = raw
        self.targetRaw = targetRaw
    }

    public static func parse(_ bytes: [UInt8]) -> FitnessMachineFeatures? {
        var r = ByteReader(bytes)
        guard let a = r.u32(), let b = r.u32() else { return nil }
        return FitnessMachineFeatures(raw: a, targetRaw: b)
    }

    public var supportsCadence: Bool { raw & (1 << 1) != 0 }
    public var supportsPowerMeasurement: Bool { raw & (1 << 14) != 0 }
    public var supportsHeartRate: Bool { raw & (1 << 10) != 0 }
    public var supportsResistanceTarget: Bool { targetRaw & (1 << 2) != 0 }
    public var supportsPowerTarget: Bool { targetRaw & (1 << 3) != 0 }
    public var supportsSimulation: Bool { targetRaw & (1 << 13) != 0 }
}

/// Supported Power Range (0x2AD8).
public struct SupportedPowerRange: Equatable, Sendable {
    public var minW: Int
    public var maxW: Int
    public var incrementW: Int

    public static func parse(_ bytes: [UInt8]) -> SupportedPowerRange? {
        var r = ByteReader(bytes)
        guard let lo = r.s16(), let hi = r.s16(), let inc = r.u16() else { return nil }
        return SupportedPowerRange(minW: Int(lo), maxW: Int(hi), incrementW: Int(inc))
    }

    public func clamp(_ watts: Double) -> Double {
        Interp.clamp(watts, Double(minW), Double(maxW))
    }
}

/// Commands written to the Fitness Machine Control Point (0x2AD9).
public enum FTMSCommand: Equatable, Sendable {
    case requestControl
    case reset
    case startOrResume
    case stop
    case pause
    case setTargetPower(watts: Int)
    /// Simulation: grade in %, wind in m/s, crr and wind resistance coefficient (kg/m).
    case setSimulation(gradePercent: Double, windSpeed: Double, crr: Double, windResistance: Double)

    public var opcode: UInt8 {
        switch self {
        case .requestControl: return 0x00
        case .reset: return 0x01
        case .setTargetPower: return 0x05
        case .startOrResume: return 0x07
        case .stop, .pause: return 0x08
        case .setSimulation: return 0x11
        }
    }

    public var bytes: [UInt8] {
        func le16(_ v: Int16) -> [UInt8] {
            let u = UInt16(bitPattern: v)
            return [UInt8(u & 0xFF), UInt8(u >> 8)]
        }
        func sat16(_ v: Double) -> Int16 { Int16(Interp.clamp(v.rounded(), Double(Int16.min), Double(Int16.max))) }
        func satU8(_ v: Double) -> UInt8 { UInt8(Interp.clamp(v.rounded(), 0, 255)) }
        switch self {
        case .requestControl, .reset, .startOrResume:
            return [opcode]
        case .stop:
            return [opcode, 0x01]
        case .pause:
            return [opcode, 0x02]
        case .setTargetPower(let w):
            return [opcode] + le16(sat16(Double(w)))
        case .setSimulation(let grade, let wind, let crr, let cw):
            return [opcode] + le16(sat16(wind * 1000)) + le16(sat16(grade * 100)) + [satU8(crr * 10000), satU8(cw * 100)]
        }
    }
}

/// Response indication from the control point: [0x80, requestOpcode, result].
public struct FTMSControlResponse: Equatable, Sendable {
    public enum Result: UInt8, Sendable {
        case success = 0x01, notSupported = 0x02, invalidParameter = 0x03, failed = 0x04, controlNotPermitted = 0x05
    }
    public var requestOpcode: UInt8
    public var result: Result?

    public static func parse(_ bytes: [UInt8]) -> FTMSControlResponse? {
        guard bytes.count >= 3, bytes[0] == 0x80 else { return nil }
        return FTMSControlResponse(requestOpcode: bytes[1], result: Result(rawValue: bytes[2]))
    }
}

// MARK: - Cycling Power Service (power meters, many trainers)

public struct CyclingPowerMeasurement: Equatable, Sendable {
    public var powerW: Int
    /// Percent of power from the left/right pedal reference, when reported.
    public var pedalBalancePercent: Double?
    public var cumulativeWheelRevs: UInt32?
    /// 1/2048 s
    public var lastWheelEventTime: UInt16?
    public var cumulativeCrankRevs: UInt16?
    /// 1/1024 s
    public var lastCrankEventTime: UInt16?

    public static func parse(_ bytes: [UInt8]) -> CyclingPowerMeasurement? {
        var r = ByteReader(bytes)
        guard let flags = r.u16(), let power = r.s16() else { return nil }
        var m = CyclingPowerMeasurement(powerW: Int(power))
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }
        if has(0) { guard let v = r.u8() else { return nil }; m.pedalBalancePercent = Double(v) / 2 }
        if has(2) { guard r.skip(2) else { return nil } } // accumulated torque
        if has(4) {
            guard let revs = r.u32(), let t = r.u16() else { return nil }
            m.cumulativeWheelRevs = revs
            m.lastWheelEventTime = t
        }
        if has(5) {
            guard let revs = r.u16(), let t = r.u16() else { return nil }
            m.cumulativeCrankRevs = revs
            m.lastCrankEventTime = t
        }
        // Remaining optional fields (extreme forces/torques/angles, dead spots,
        // energy) are not needed.
        return m
    }
}

// MARK: - Heart Rate Service

public struct HeartRateMeasurement: Equatable, Sendable {
    public var bpm: Int
    /// nil when the sensor doesn't report contact status.
    public var sensorContact: Bool?
    /// RR intervals in seconds.
    public var rrIntervals: [Double]

    public static func parse(_ bytes: [UInt8]) -> HeartRateMeasurement? {
        var r = ByteReader(bytes)
        guard let flags = r.u8() else { return nil }
        let bpm: Int
        if flags & 0x01 != 0 {
            guard let v = r.u16() else { return nil }
            bpm = Int(v)
        } else {
            guard let v = r.u8() else { return nil }
            bpm = Int(v)
        }
        let contactSupported = flags & 0x04 != 0
        let contact: Bool? = contactSupported ? (flags & 0x02 != 0) : nil
        if flags & 0x08 != 0 { guard r.skip(2) else { return nil } } // energy expended
        var rr: [Double] = []
        if flags & 0x10 != 0 {
            while let v = r.u16() { rr.append(Double(v) / 1024) }
        }
        return HeartRateMeasurement(bpm: bpm, sensorContact: contact, rrIntervals: rr)
    }
}

// MARK: - Cycling Speed & Cadence Service

public struct CSCMeasurement: Equatable, Sendable {
    public var cumulativeWheelRevs: UInt32?
    /// 1/1024 s
    public var lastWheelEventTime: UInt16?
    public var cumulativeCrankRevs: UInt16?
    /// 1/1024 s
    public var lastCrankEventTime: UInt16?

    public static func parse(_ bytes: [UInt8]) -> CSCMeasurement? {
        var r = ByteReader(bytes)
        guard let flags = r.u8() else { return nil }
        var m = CSCMeasurement()
        if flags & 0x01 != 0 {
            guard let revs = r.u32(), let t = r.u16() else { return nil }
            m.cumulativeWheelRevs = revs
            m.lastWheelEventTime = t
        }
        if flags & 0x02 != 0 {
            guard let revs = r.u16(), let t = r.u16() else { return nil }
            m.cumulativeCrankRevs = revs
            m.lastCrankEventTime = t
        }
        return m
    }
}

/// Turns cumulative crank revolution events (CPS or CSC) into cadence,
/// handling 16-bit wrap-around and dropping to zero when pedalling stops.
public struct CrankCadenceCalculator: Sendable {
    private var lastRevs: UInt16?
    private var lastEventTime: UInt16?
    private var lastChangeAt: Double?
    public private(set) var cadence: Double?
    /// Seconds without a new crank event before cadence is reported as 0.
    public var stopTimeout: Double = 2.5

    public init() {}

    /// - Parameters:
    ///   - eventTime: last crank event time in 1/1024 s.
    ///   - now: local monotonic clock in seconds.
    @discardableResult
    public mutating func update(revs: UInt16, eventTime: UInt16, now: Double) -> Double? {
        defer {
            lastRevs = revs
            lastEventTime = eventTime
        }
        guard let pr = lastRevs, let pt = lastEventTime else {
            lastChangeAt = now
            return cadence
        }
        let dRevs = revs &- pr // wraps correctly in UInt16
        let dTicks = eventTime &- pt
        if dRevs > 0 && dTicks > 0 && dRevs < 50 {
            let rpm = Double(dRevs) / (Double(dTicks) / 1024) * 60
            if rpm < 250 {
                cadence = rpm
                lastChangeAt = now
            }
        } else if let lc = lastChangeAt, now - lc > stopTimeout {
            cadence = 0
        }
        return cadence
    }

    /// Call periodically so cadence decays to 0 when notifications stop.
    public mutating func tick(now: Double) {
        if let lc = lastChangeAt, now - lc > stopTimeout { cadence = 0 }
    }
}
