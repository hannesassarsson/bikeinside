import BikeinsideCore
import SwiftUI
import UniformTypeIdentifiers

/// Today's form on the start screen: Garmin data + quick check-in, with a
/// concrete suggestion for the selected workout.
struct ReadinessCard: View {
    @Environment(AppModel.self) private var model
    @State private var showingCheckIn = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Dagsform")
                    Spacer()
                    if let st = model.healthStatus {
                        Text(st).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    Button(model.todayCheckIn == nil ? "Checka in" : "Ändra incheckning") { showingCheckIn = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if let r = model.readiness {
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.1), lineWidth: 7)
                            Circle().trim(from: 0, to: CGFloat(r.score) / 100)
                                .stroke(color(r), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(r.score)").font(.system(size: 20, weight: .heavy, design: .rounded))
                        }
                        .frame(width: 62, height: 62)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.title).font(.system(size: 16, weight: .bold)).foregroundStyle(color(r))
                            Text(r.reasons.prefix(4).joined(separator: " · "))
                                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            Text("Källa: \(r.source)").font(.system(size: 10)).foregroundStyle(Theme.textSecondary.opacity(0.7))
                            suggestion(r)
                        }
                    }
                } else {
                    Text(model.garminToken == nil
                         ? "Checka in med hur benen känns, eller koppla Garmin under Profil så anpassas dagens pass efter sömn, HRV och vilopuls."
                         : "Ingen data för idag ännu. Checka in med hur du känner dig.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showingCheckIn) { CheckInSheet() }
    }

    private func color(_ r: Readiness) -> Color {
        switch r.advice {
        case .asPlanned: return Theme.good
        case .reduce: return Theme.warn
        case .easier: return Theme.accent
        case .rest: return Theme.bad
        }
    }

    @ViewBuilder
    private func suggestion(_ r: Readiness) -> some View {
        let planned = model.selectedWorkout
        if let alt = r.alternative(for: planned, ftp: model.profile.ftp) {
            HStack {
                Text("Förslag: kör \(alt.name) i stället för \(planned?.name ?? "fri cykling").").font(.system(size: 12, weight: .semibold))
                Button("Byt") { model.selectedWorkoutId = alt.id }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
        } else if case .reduce(let m) = r.advice, planned != nil {
            Text("Passet startar på \(Int((m * 100).rounded())) % intensitet (justera med + / − under åkningen).")
                .font(.system(size: 12, weight: .semibold)).padding(.top, 4)
        }
    }
}

struct CheckInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var legs = 3
    @State private var energy = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hur känns kroppen idag?").font(.system(size: 22, weight: .heavy, design: .rounded))
            scale("Benen", $legs, ["Döda", "Tunga", "Okej", "Pigga", "Raketer"])
            scale("Energin", $energy, ["Slut", "Låg", "Normal", "Bra", "Topp"])
            HStack {
                Spacer()
                Button("Avbryt") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Spara") {
                    model.checkIn = CheckIn(legs: legs, energy: energy)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .onAppear {
            if let c = model.todayCheckIn { legs = c.legs; energy = c.energy }
        }
    }

    private func scale(_ title: String, _ value: Binding<Int>, _ labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .bold))
            Picker(title, selection: value) {
                ForEach(1...5, id: \.self) { i in Text(labels[i - 1]).tag(i) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// Garmin connection (token for garmin-bridge) in Profile.
struct GarminCard: View {
    @Environment(AppModel.self) private var model
    @State private var tokenInput = ""

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Garmin (dagsform)")
                Text("Klistra in din coach-token från garmin-bridge. Bikeinside läser bara sömn, HRV, vilopuls, Body Battery och Training Readiness för att anpassa dagens pass. Token sparas i macOS-nyckelringen.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                if model.garminToken == nil {
                    HStack {
                        SecureField("Token", text: $tokenInput).textFieldStyle(.roundedBorder).frame(width: 320)
                        Button("Koppla") { model.setGarminToken(tokenInput); tokenInput = "" }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    HStack {
                        Label(model.healthStatus ?? "Kopplad – \(model.healthDays.count) dagar med data", systemImage: "heart.text.square.fill")
                            .foregroundStyle(model.healthStatus == nil ? Theme.good : Theme.warn)
                        Spacer()
                        Button("Uppdatera") { model.refreshHealth() }.buttonStyle(SecondaryButtonStyle())
                        Button("Koppla från") { model.setGarminToken(nil) }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

/// Card on the start screen that imports a GPX file as a new world.
struct ImportGPXCard: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var pendingURL: URL?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text("Cykla din egen runda").font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Importera en GPX-fil från Strava, Garmin eller RideWithGPS – så bygger appen en värld med rätt kurvor och backar.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button("Importera GPX…") { importing = true }.buttonStyle(PrimaryButtonStyle())
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Theme.warn).multilineTextAlignment(.center) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 270)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml]) { result in
            if case .success(let url) = result { pendingURL = url }
        }
        .confirmationDialog("Vilken miljö ska rundan få?", isPresented: Binding(get: { pendingURL != nil }, set: { if !$0 { pendingURL = nil } })) {
            Button("Skog") { importFile(.forest) }
            Button("Fjäll") { importFile(.mountain) }
            Button("Avbryt", role: .cancel) { pendingURL = nil }
        }
    }

    private func importFile(_ theme: SceneryTheme) {
        guard let url = pendingURL else { return }
        pendingURL = nil
        do {
            _ = try model.importGPX(from: url, theme: theme)
            error = nil
        } catch GPXImport.ImportError.tooLong(let km) {
            error = "Rutten är \(km) km – max \(Int(GPXImport.maxLength / 1000)) km stöds."
        } catch GPXImport.ImportError.tooShort {
            error = "Rutten är för kort (minst 500 m)."
        } catch {
            self.error = "Kunde inte läsa GPX-filen."
        }
    }
}
