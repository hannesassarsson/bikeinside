import BikeinsideCore
import CoreBluetooth
import Foundation
import Observation

/// A sensor seen while scanning.
struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Roles the device can fill based on its advertised services.
    var capabilities: Set<SensorRole>
    var rssi: Int
    var lastSeen: Date
}

/// Live state for one connected (or connecting) device.
struct DeviceLink: Equatable {
    enum Status: Equatable { case connecting, discovering, connected, disconnected }
    var id: UUID
    var name: String
    var role: SensorRole
    var status: Status
    var supportsControl = false
    var batteryLevel: Int?
    var lastValue: String = ""
}

/// CoreBluetooth central for smart trainers (FTMS / CPS), power meters (CPS),
/// heart-rate straps (HRS) and cadence sensors (CSC).
///
/// All callbacks arrive on the main queue; parsing and trainer control logic
/// live in BikeinsideCore and are unit tested there.
@MainActor
@Observable
final class BluetoothManager: NSObject {
    enum RadioState: Equatable {
        case unknown, poweredOff, unauthorized, unsupported, ready

        var message: String? {
            switch self {
            case .unknown: return "Startar Bluetooth…"
            case .poweredOff: return "Bluetooth är avstängt. Slå på det i Kontrollcenter."
            case .unauthorized: return "Bikeinside har inte tillgång till Bluetooth. Tillåt det i Systeminställningar → Integritet och säkerhet → Bluetooth."
            case .unsupported: return "Den här datorn saknar stöd för Bluetooth LE."
            case .ready: return nil
            }
        }
    }

    private(set) var radio: RadioState = .unknown
    private(set) var isScanning = false
    private(set) var discovered: [DiscoveredDevice] = []
    /// Connected device per role.
    private(set) var links: [SensorRole: DeviceLink] = [:]
    private(set) var trainerFeatures: FitnessMachineFeatures?
    private(set) var trainerPowerRange: SupportedPowerRange?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var roleByPeripheral: [UUID: SensorRole] = [:]
    @ObservationIgnored private var controlPoint: CBCharacteristic?
    @ObservationIgnored private var hub = SensorHub()
    @ObservationIgnored private var control = TrainerControlState()
    @ObservationIgnored private var cadenceCalcs: [UUID: CrankCadenceCalculator] = [:]
    @ObservationIgnored private var scanStopTask: Task<Void, Never>?

    private static let savedKey = "savedDevices"

    static let serviceUUIDs: [CBUUID] = [
        GATT.fitnessMachineService, GATT.cyclingPowerService, GATT.heartRateService, GATT.cyclingSpeedCadenceService,
    ].map(CBUUID.uuid16)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: Public API

    var now: Double { ProcessInfo.processInfo.systemUptime }

    func inputs() -> RideInputs {
        let t = now
        for id in cadenceCalcs.keys { cadenceCalcs[id]?.tick(now: t) }
        return hub.inputs(now: t)
    }

    func powerSource() -> SensorRole? { hub.powerSource(now: now) }

    var trainerConnected: Bool { links[.trainer]?.status == .connected }
    var trainerControllable: Bool { trainerConnected && controlPoint != nil }
    var trainerControlError: String? { control.lastError }

    func setTrainerTarget(_ t: TrainerTarget) {
        control.setTarget(t)
        pump()
    }

    /// Writes the next queued FTMS command if the control point is free. Call ~10 Hz.
    func pump() {
        guard let cp = controlPoint, let p = cp.service?.peripheral, p.state == .connected else { return }
        if let cmd = control.nextCommand(now: now) {
            p.writeValue(Data(cmd.bytes), for: cp, type: .withResponse)
        }
    }

    func startScan(duration: TimeInterval = 20) {
        guard radio == .ready else { return }
        discovered.removeAll()
        central.scanForPeripherals(withServices: Self.serviceUUIDs, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        scanStopTask?.cancel()
        scanStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        scanStopTask?.cancel()
        if central.isScanning { central.stopScan() }
        isScanning = false
    }

    func connect(_ device: DiscoveredDevice, as role: SensorRole) {
        // one device per role; a device can only fill one role at a time
        if let existing = links[role], existing.id != device.id { disconnect(role: role) }
        if let otherRole = roleByPeripheral[device.id], otherRole != role { disconnect(role: otherRole) }
        guard let p = peripherals[device.id] ?? central.retrievePeripherals(withIdentifiers: [device.id]).first else { return }
        attach(p, role: role, name: device.name)
        saveDevices()
    }

    func disconnect(role: SensorRole) {
        guard let link = links[role] else { return }
        links[role] = nil
        roleByPeripheral[link.id] = nil
        hub.remove(role: role)
        if role == .trainer {
            controlPoint = nil
            control.disconnect()
            trainerFeatures = nil
            trainerPowerRange = nil
        }
        if let p = peripherals[link.id] { central.cancelPeripheralConnection(p) }
        saveDevices()
    }

    // MARK: Internals

    private func attach(_ p: CBPeripheral, role: SensorRole, name: String) {
        peripherals[p.identifier] = p
        roleByPeripheral[p.identifier] = role
        p.delegate = self
        links[role] = DeviceLink(id: p.identifier, name: name, role: role, status: .connecting)
        central.connect(p, options: nil)
    }

    private struct SavedDevice: Codable {
        var id: UUID
        var name: String
        var role: SensorRole
    }

    private func saveDevices() {
        let saved = links.values.map { SavedDevice(id: $0.id, name: $0.name, role: $0.role) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.savedKey)
        }
    }

    /// Reconnects to the devices used last time (they connect whenever they wake up).
    private func restoreSavedDevices() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode([SavedDevice].self, from: data) else { return }
        for s in saved where links[s.role] == nil {
            if let p = central.retrievePeripherals(withIdentifiers: [s.id]).first {
                attach(p, role: s.role, name: s.name)
            }
        }
    }

    private func role(for p: CBPeripheral) -> SensorRole? { roleByPeripheral[p.identifier] }

    private func update(_ role: SensorRole, _ change: (inout DeviceLink) -> Void) {
        guard var l = links[role] else { return }
        change(&l)
        links[role] = l
    }

    private func handleValue(_ bytes: [UInt8], characteristic uuid: CBUUID, peripheral p: CBPeripheral) {
        guard let role = role(for: p), let short = uuid.short16 else { return }
        let t = now
        switch short {
        case GATT.indoorBikeData:
            guard role == .trainer, let d = IndoorBikeData.parse(bytes) else { return }
            hub.ingest(role: .trainer, power: d.powerW.map(Double.init), cadence: d.cadenceRpm, heartRate: d.heartRateBpm, now: t)
            if let w = d.powerW { update(role) { $0.lastValue = "\(w) W" + (d.cadenceRpm.map { " · \(Int($0)) rpm" } ?? "") } }

        case GATT.cyclingPowerMeasurement:
            // A trainer that also has FTMS reports through Indoor Bike Data instead.
            if role == .trainer && links[.trainer]?.supportsControl == true && controlPoint != nil { return }
            guard let m = CyclingPowerMeasurement.parse(bytes) else { return }
            var cadence: Double?
            if let revs = m.cumulativeCrankRevs, let time = m.lastCrankEventTime {
                cadence = cadenceCalcs[p.identifier, default: CrankCadenceCalculator()].update(revs: revs, eventTime: time, now: t)
            }
            hub.ingest(role: role, power: Double(m.powerW), cadence: cadence, now: t)
            update(role) { $0.lastValue = "\(m.powerW) W" + (cadence.map { " · \(Int($0)) rpm" } ?? "") }

        case GATT.heartRateMeasurement:
            guard let m = HeartRateMeasurement.parse(bytes) else { return }
            if m.sensorContact == false { return }
            hub.ingest(role: role == .trainer ? .trainer : .heartRate, heartRate: m.bpm, now: t)
            update(role) { $0.lastValue = "\(m.bpm) bpm" }

        case GATT.cscMeasurement:
            guard let m = CSCMeasurement.parse(bytes), let revs = m.cumulativeCrankRevs, let time = m.lastCrankEventTime else { return }
            let c = cadenceCalcs[p.identifier, default: CrankCadenceCalculator()].update(revs: revs, eventTime: time, now: t)
            hub.ingest(role: .cadence, cadence: c, now: t)
            if let c { update(role) { $0.lastValue = "\(Int(c)) rpm" } }

        case GATT.fitnessMachineControlPoint:
            if let r = FTMSControlResponse.parse(bytes) {
                control.handle(r, now: t)
                pump()
            }

        case GATT.fitnessMachineFeature:
            trainerFeatures = FitnessMachineFeatures.parse(bytes)

        case GATT.supportedPowerRange:
            trainerPowerRange = SupportedPowerRange.parse(bytes)

        case GATT.batteryLevel:
            if let b = bytes.first { update(role) { $0.batteryLevel = Int(b) } }

        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            switch state {
            case .poweredOn:
                radio = .ready
                restoreSavedDevices()
            case .poweredOff: radio = .poweredOff
            case .unauthorized: radio = .unauthorized
            case .unsupported: radio = .unsupported
            default: radio = .unknown
            }
            if state != .poweredOn { isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            peripherals[peripheral.identifier] = peripheral
            var caps = Set<SensorRole>()
            if services.contains(.uuid16(GATT.fitnessMachineService)) { caps.insert(.trainer) }
            if services.contains(.uuid16(GATT.cyclingPowerService)) {
                caps.insert(.powerMeter)
                caps.insert(.trainer) // many trainers only expose CPS
            }
            if services.contains(.uuid16(GATT.heartRateService)) { caps.insert(.heartRate) }
            if services.contains(.uuid16(GATT.cyclingSpeedCadenceService)) { caps.insert(.cadence) }
            let name = localName ?? peripheral.name ?? "Okänd enhet"
            if let i = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
                discovered[i].rssi = rssi
                discovered[i].lastSeen = Date()
                discovered[i].capabilities.formUnion(caps)
                if localName != nil { discovered[i].name = name }
            } else {
                discovered.append(DiscoveredDevice(id: peripheral.identifier, name: name, capabilities: caps, rssi: rssi, lastSeen: Date()))
                discovered.sort { $0.rssi > $1.rssi }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard let role = role(for: peripheral) else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            update(role) { $0.status = .discovering }
            peripheral.discoverServices(Self.serviceUUIDs + [.uuid16(GATT.batteryService)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard let role = role(for: peripheral) else { return }
            update(role) { $0.status = .disconnected }
            // keep trying: the device may be asleep
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard let role = role(for: peripheral) else { return }
            update(role) { $0.status = .disconnected }
            hub.remove(role: role)
            if role == .trainer {
                controlPoint = nil
                control.disconnect()
            }
            // auto-reconnect while the device is still assigned
            central.connect(peripheral, options: nil)
            update(role) { $0.status = .connecting }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let role = role(for: peripheral) else { return }
            let services = peripheral.services ?? []
            let hasFTMS = services.contains { $0.uuid == .uuid16(GATT.fitnessMachineService) }
            for s in services {
                // A power meter role only needs CPS; a trainer prefers FTMS when available.
                if role == .powerMeter && s.uuid == .uuid16(GATT.fitnessMachineService) { continue }
                if role == .trainer && hasFTMS && s.uuid == .uuid16(GATT.cyclingPowerService) { continue }
                peripheral.discoverCharacteristics(nil, for: s)
            }
            update(role) { $0.supportsControl = (role == .trainer && hasFTMS) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard let role = role(for: peripheral) else { return }
            for c in service.characteristics ?? [] {
                switch c.uuid.short16 ?? 0 {
                case GATT.indoorBikeData, GATT.cyclingPowerMeasurement, GATT.heartRateMeasurement, GATT.cscMeasurement:
                    peripheral.setNotifyValue(true, for: c)
                case GATT.fitnessMachineControlPoint where role == .trainer:
                    peripheral.setNotifyValue(true, for: c) // indications
                case GATT.fitnessMachineStatus where role == .trainer:
                    peripheral.setNotifyValue(true, for: c)
                case GATT.fitnessMachineFeature, GATT.supportedPowerRange, GATT.batteryLevel:
                    peripheral.readValue(for: c)
                default:
                    break
                }
            }
            update(role) { $0.status = .connected }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let isCP = characteristic.uuid == .uuid16(GATT.fitnessMachineControlPoint)
        let ok = error == nil && characteristic.isNotifying
        MainActor.assumeIsolated {
            guard isCP, ok, role(for: peripheral) == .trainer else { return }
            controlPoint = characteristic
            control.connect()
            pump()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let uuid = characteristic.uuid
        MainActor.assumeIsolated {
            handleValue(bytes, characteristic: uuid, peripheral: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // Responses arrive as indications on the control point; write errors are
        // recovered by the control state machine's timeout.
    }
}

extension CBUUID {
    static func uuid16(_ v: UInt16) -> CBUUID {
        CBUUID(string: String(format: "%04X", v))
    }

    /// The 16-bit SIG value for short UUIDs (or base-UUID long forms), else nil.
    var short16: UInt16? {
        let d = data
        if d.count == 2 { return UInt16(d[0]) << 8 | UInt16(d[1]) }
        // 0000xxxx-0000-1000-8000-00805F9B34FB
        if d.count == 16, uuidString.hasSuffix("-0000-1000-8000-00805F9B34FB"), d[0] == 0, d[1] == 0 {
            return UInt16(d[2]) << 8 | UInt16(d[3])
        }
        return nil
    }
}
