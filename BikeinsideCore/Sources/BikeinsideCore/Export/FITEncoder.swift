import Foundation

/// Writes a Garmin FIT activity file (sport: cycling / virtual activity) that
/// Strava, Garmin Connect, TrainingPeaks and intervals.icu accept.
/// Only the messages needed for an indoor ride are emitted.
public enum FITEncoder {
    /// Seconds between the Unix epoch and the FIT epoch (1989-12-31 00:00:00 UTC).
    public static let fitEpochOffset: TimeInterval = 631_065_600

    enum BaseType: UInt8 {
        case enumT = 0x00, uint8 = 0x02, uint16 = 0x84, uint32 = 0x86, uint32z = 0x8C, sint32 = 0x85

        var size: Int {
            switch self {
            case .enumT, .uint8: return 1
            case .uint16: return 2
            case .uint32, .uint32z, .sint32: return 4
            }
        }

        var invalid: UInt64 {
            switch self {
            case .enumT, .uint8: return 0xFF
            case .uint16: return 0xFFFF
            case .uint32: return 0xFFFF_FFFF
            case .uint32z: return 0
            case .sint32: return 0x7FFF_FFFF
            }
        }
    }

    struct Field {
        var number: UInt8
        var type: BaseType
    }

    struct Message {
        var global: UInt16
        var local: UInt8
        var fields: [Field]
    }

    // Global message numbers
    static let fileId = Message(global: 0, local: 0, fields: [
        Field(number: 0, type: .enumT),   // type = activity (4)
        Field(number: 1, type: .uint16),  // manufacturer = development (255)
        Field(number: 2, type: .uint16),  // product
        Field(number: 3, type: .uint32z), // serial
        Field(number: 4, type: .uint32),  // time_created
    ])
    static let event = Message(global: 21, local: 1, fields: [
        Field(number: 253, type: .uint32), // timestamp
        Field(number: 0, type: .enumT),    // event = timer (0)
        Field(number: 1, type: .enumT),    // event_type start(0) / stop_all(4)
    ])
    static let record = Message(global: 20, local: 2, fields: [
        Field(number: 253, type: .uint32), // timestamp
        Field(number: 5, type: .uint32),   // distance (m * 100)
        Field(number: 6, type: .uint16),   // speed (m/s * 1000)
        Field(number: 2, type: .uint16),   // altitude ((m + 500) * 5)
        Field(number: 7, type: .uint16),   // power (W)
        Field(number: 3, type: .uint8),    // heart_rate
        Field(number: 4, type: .uint8),    // cadence
    ])
    static let lap = Message(global: 19, local: 3, fields: [
        Field(number: 253, type: .uint32), // timestamp
        Field(number: 2, type: .uint32),   // start_time
        Field(number: 7, type: .uint32),   // total_elapsed_time (s * 1000)
        Field(number: 8, type: .uint32),   // total_timer_time (s * 1000)
        Field(number: 9, type: .uint32),   // total_distance (m * 100)
        Field(number: 19, type: .uint16),  // avg_power
        Field(number: 20, type: .uint16),  // max_power
        Field(number: 0, type: .enumT),    // event = lap (9)
        Field(number: 1, type: .enumT),    // event_type = stop (1)
        Field(number: 25, type: .enumT),   // sport = cycling (2)
    ])
    static let session = Message(global: 18, local: 4, fields: [
        Field(number: 253, type: .uint32), // timestamp
        Field(number: 2, type: .uint32),   // start_time
        Field(number: 7, type: .uint32),   // total_elapsed_time
        Field(number: 8, type: .uint32),   // total_timer_time
        Field(number: 9, type: .uint32),   // total_distance
        Field(number: 11, type: .uint16),  // total_calories (kcal)
        Field(number: 14, type: .uint16),  // avg_speed
        Field(number: 15, type: .uint16),  // max_speed
        Field(number: 16, type: .uint8),   // avg_heart_rate
        Field(number: 17, type: .uint8),   // max_heart_rate
        Field(number: 18, type: .uint8),   // avg_cadence
        Field(number: 20, type: .uint16),  // avg_power
        Field(number: 21, type: .uint16),  // max_power
        Field(number: 22, type: .uint16),  // total_ascent (m)
        Field(number: 34, type: .uint16),  // normalized_power
        Field(number: 35, type: .uint16),  // training_stress_score (* 10)
        Field(number: 36, type: .uint16),  // intensity_factor (* 1000)
        Field(number: 25, type: .uint16),  // first_lap_index
        Field(number: 26, type: .uint16),  // num_laps
        Field(number: 0, type: .enumT),    // event = session (8)
        Field(number: 1, type: .enumT),    // event_type = stop (1)
        Field(number: 5, type: .enumT),    // sport = cycling (2)
        Field(number: 6, type: .enumT),    // sub_sport = virtual_activity (58)
    ])
    static let activity = Message(global: 34, local: 5, fields: [
        Field(number: 253, type: .uint32), // timestamp
        Field(number: 0, type: .uint32),   // total_timer_time (s * 1000)
        Field(number: 1, type: .uint16),   // num_sessions
        Field(number: 2, type: .enumT),    // type = manual (0)
        Field(number: 3, type: .enumT),    // event = activity (26)
        Field(number: 4, type: .enumT),    // event_type = stop (1)
    ])

    public static func fitTimestamp(_ date: Date) -> UInt32 {
        UInt32(max(0, date.timeIntervalSince1970 - fitEpochOffset))
    }

    public static func encode(_ ride: RideRecord) -> Data {
        var body: [UInt8] = []

        func define(_ m: Message) {
            body.append(0x40 | m.local)
            body.append(0)             // reserved
            body.append(0)             // little-endian
            body.append(UInt8(m.global & 0xFF))
            body.append(UInt8(m.global >> 8))
            body.append(UInt8(m.fields.count))
            for f in m.fields {
                body.append(f.number)
                body.append(UInt8(f.type.size))
                body.append(f.type.rawValue)
            }
        }

        /// Values are given per field in definition order; nil writes the invalid marker.
        func write(_ m: Message, _ values: [UInt64?]) {
            precondition(values.count == m.fields.count)
            body.append(m.local)
            for (f, v) in zip(m.fields, values) {
                var raw = v ?? f.type.invalid
                // keep valid values below the invalid sentinel
                if v != nil, f.type != .uint32z, raw >= f.type.invalid { raw = f.type.invalid - 1 }
                for k in 0..<f.type.size { body.append(UInt8((raw >> (8 * UInt64(k))) & 0xFF)) }
            }
        }

        func u(_ v: Double) -> UInt64? { v.isFinite && v >= 0 ? UInt64(v.rounded()) : nil }

        let start = fitTimestamp(ride.startDate)
        let samples = ride.samples
        let lastT = UInt32(samples.last?.t ?? 0)
        let end = start + max(lastT, UInt32(ride.stats.duration))
        let s = ride.stats

        define(fileId)
        write(fileId, [4, 255, 1, 0x00B1_4E51, UInt64(start)])

        define(event)
        write(event, [UInt64(start), 0, 0])

        define(record)
        for smp in samples {
            write(record, [
                UInt64(start + UInt32(smp.t)),
                u(smp.distance * 100),
                u(smp.speed * 1000),
                u((smp.elevation + 500) * 5),
                u(Double(max(smp.power, 0))),
                smp.heartRate.map { UInt64($0) },
                smp.cadence.map { UInt64(max($0, 0)) },
            ])
        }

        write(event, [UInt64(end), 0, 4])

        let timer = UInt64(s.duration) * 1000
        let elapsedMs = UInt64(max(ride.elapsedSeconds, s.duration)) * 1000
        define(lap)
        write(lap, [UInt64(end), UInt64(start), elapsedMs, timer, u(s.distance * 100), u(s.averagePower), UInt64(s.maxPower), 9, 1, 2])

        define(session)
        write(session, [
            UInt64(end), UInt64(start), elapsedMs, timer, u(s.distance * 100),
            u(s.kilojoules * 1.0), // ≈ kcal burned for ~24 % gross efficiency
            u(s.averageSpeed * 1000), u(s.maxSpeed * 1000),
            s.averageHeartRate.map { UInt64($0) }, s.maxHeartRate.map { UInt64($0) },
            s.averageCadence.map { UInt64($0) },
            u(s.averagePower), UInt64(s.maxPower), u(s.ascent), u(s.normalizedPower),
            u(s.tss * 10), u(s.intensityFactor * 1000), 0, 1, 8, 1, 2, 58,
        ])

        define(activity)
        write(activity, [UInt64(end), timer, 1, 0, 26, 1])

        // Header (14 bytes) with its own CRC, then body, then file CRC.
        var header: [UInt8] = [14, 0x20]
        let profileVersion: UInt16 = 2132
        header += [UInt8(profileVersion & 0xFF), UInt8(profileVersion >> 8)]
        let size = UInt32(body.count)
        header += (0..<4).map { UInt8((size >> (8 * $0)) & 0xFF) }
        header += Array(".FIT".utf8)
        let hcrc = crc16(header)
        header += [UInt8(hcrc & 0xFF), UInt8(hcrc >> 8)]

        var file = header + body
        let fcrc = crc16(file)
        file += [UInt8(fcrc & 0xFF), UInt8(fcrc >> 8)]
        return Data(file)
    }

    /// FIT CRC-16 (same as CRC-16/ARC).
    public static func crc16(_ bytes: [UInt8], seed: UInt16 = 0) -> UInt16 {
        let table: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
        ]
        var crc = seed
        for b in bytes {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(b & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((b >> 4) & 0xF)]
        }
        return crc
    }
}
