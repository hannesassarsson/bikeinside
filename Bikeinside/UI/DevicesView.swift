import BikeinsideCore
import SwiftUI

struct DevicesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bt = model.bluetooth
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enheter").font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("Anslut smart trainer, wattmätare, pulsband eller kadenssensor via Bluetooth. Enheterna kopplas in automatiskt nästa gång.")
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    bt.isScanning ? bt.stopScan() : bt.startScan()
                } label: {
                    Label(bt.isScanning ? "Sluta söka" : "Sök efter enheter", systemImage: bt.isScanning ? "stop.circle" : "magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(bt.radio != .ready)
            }

            if let msg = bt.radio.message {
                Card {
                    Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                }
            }

            SectionTitle("Anslutna")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(SensorRole.allCases, id: \.self) { role in
                    RoleCard(role: role, link: bt.links[role]) { bt.disconnect(role: role) }
                }
            }
            if let f = bt.trainerFeatures {
                Text("Trainern stödjer: " + [
                    f.supportsSimulation ? "backsimulering" : nil,
                    f.supportsPowerTarget ? "ERG-läge" : nil,
                    f.supportsPowerMeasurement ? "wattmätning" : nil,
                    f.supportsCadence ? "kadens" : nil,
                ].compactMap { $0 }.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack {
                SectionTitle("Hittade enheter")
                if bt.isScanning { ProgressView().controlSize(.small).padding(.leading, 6) }
            }
            if bt.discovered.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bt.isScanning ? "Letar…" : "Tryck på \"Sök efter enheter\".")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Tips: trampa några varv för att väcka trainern, och fukta pulsbandet. Stäng appar på telefonen som kan vara anslutna till samma enhet (Bluetooth-enheter tillåter ofta bara en anslutning).")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(bt.discovered) { d in
                        DiscoveredRow(device: d, connectedRole: bt.links.first { $0.value.id == d.id }?.key) { role in
                            bt.connect(d, as: role)
                        }
                    }
                }
            }
        }
    }
}

private struct RoleCard: View {
    let role: SensorRole
    let link: DeviceLink?
    let disconnect: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(link == nil ? Theme.textSecondary : Theme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(role.displayName).font(.system(size: 15, weight: .bold))
                    if let link {
                        HStack(spacing: 6) {
                            Circle().fill(statusColor(link.status)).frame(width: 7, height: 7)
                            Text(link.name).font(.system(size: 12, weight: .semibold))
                            Text(statusText(link.status)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            if let b = link.batteryLevel {
                                Label("\(b) %", systemImage: "battery.75").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if !link.lastValue.isEmpty {
                            Text(link.lastValue).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                    } else {
                        Text("Inte ansluten").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if link != nil {
                    Button("Koppla från", action: disconnect).buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var symbol: String {
        switch role {
        case .trainer: return "figure.indoor.cycle"
        case .powerMeter: return "bolt.fill"
        case .heartRate: return "heart.fill"
        case .cadence: return "arrow.triangle.2.circlepath"
        }
    }

    private func statusColor(_ s: DeviceLink.Status) -> Color {
        switch s {
        case .connected: return Theme.good
        case .connecting, .discovering: return Theme.warn
        case .disconnected: return Theme.bad
        }
    }

    private func statusText(_ s: DeviceLink.Status) -> String {
        switch s {
        case .connected: return "ansluten"
        case .connecting: return "ansluter…"
        case .discovering: return "läser tjänster…"
        case .disconnected: return "frånkopplad"
        }
    }
}

private struct DiscoveredRow: View {
    let device: DiscoveredDevice
    let connectedRole: SensorRole?
    let connect: (SensorRole) -> Void

    var body: some View {
        HStack(spacing: 12) {
            SignalBars(rssi: device.rssi)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(size: 14, weight: .semibold))
                Text(device.capabilities.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let connectedRole {
                Label("Ansluten som \(connectedRole.displayName.lowercased())", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.good)
            } else {
                ForEach(orderedCaps, id: \.self) { role in
                    Button("Anslut som \(role.displayName.lowercased())") { connect(role) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var orderedCaps: [SensorRole] {
        SensorRole.allCases.filter { device.capabilities.contains($0) }
    }
}

private struct SignalBars: View {
    let rssi: Int

    var body: some View {
        let level = rssi > -60 ? 3 : (rssi > -75 ? 2 : 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Theme.good : .white.opacity(0.2))
                    .frame(width: 4, height: CGFloat(4 + i * 4))
            }
        }
        .frame(width: 20)
        .help("Signalstyrka \(rssi) dBm")
    }
}
