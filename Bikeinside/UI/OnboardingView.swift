import BikeinsideCore
import SwiftUI

/// First-launch setup: who you are and what you ride on.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: profile(model: model)
                default: devices
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle().fill(i == page ? Theme.accent : .white.opacity(0.2)).frame(width: 8, height: 8)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Tillbaka") { page -= 1 }.buttonStyle(SecondaryButtonStyle())
                }
                Button(page == 2 ? "Kom igång" : "Nästa") {
                    if page == 2 {
                        model.profile = model.profile.sanitized()
                        model.hasCompletedOnboarding = true
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
            .background(Theme.panel)
        }
        .frame(width: 640, height: 520)
        .background(Theme.background)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "bicycle")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Välkommen till Bikeinside")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text("Cykla inomhus genom svensk skog, runt sjöar och upp på fjället. Koppla in din smarta trainer, kör strukturerade pass eller häng på en grupp – och exportera allt till Strava eller Garmin.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: 460)
        }
    }

    private func profile(model: AppModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            Text("Om dig").font(.system(size: 26, weight: .heavy, design: .rounded))
            Text("Vikt och längd används för att räkna ut farten realistiskt. FTP styr träningspassen – gissa om du inte vet, och kör ramptestet senare.")
                .foregroundStyle(Theme.textSecondary)
            Form {
                TextField("Namn", text: $model.profile.name)
                TextField("Vikt (kg)", value: $model.profile.weightKg, format: .number)
                TextField("Längd (cm)", value: $model.profile.heightCm, format: .number)
                TextField("FTP (W)", value: $model.profile.ftp, format: .number)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var devices: some View {
        let bt = model.bluetooth
        return VStack(alignment: .leading, spacing: 16) {
            Text("Anslut din utrustning").font(.system(size: 26, weight: .heavy, design: .rounded))
            Text("Bikeinside stödjer smarta trainers med FTMS (t.ex. de flesta moderna trainers från de stora märkena), wattmätare, pulsband och kadenssensorer via Bluetooth.")
                .foregroundStyle(Theme.textSecondary)
            if let msg = bt.radio.message {
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
            }
            Button {
                bt.startScan()
                model.section = .devices
                model.hasCompletedOnboarding = true
            } label: {
                Label("Sök efter enheter nu", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(bt.radio != .ready)
            Text("Ingen trainer än? Inga problem – du kan cykla med tangentbordet (↑/↓) för att prova.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
