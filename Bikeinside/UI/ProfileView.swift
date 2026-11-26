import BikeinsideCore
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 22) {
            Text("Profil & inställningar").font(.system(size: 30, weight: .heavy, design: .rounded))

            HStack(alignment: .top, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Cyklist")
                        LabeledField("Namn") {
                            TextField("Namn", text: $model.profile.name).textFieldStyle(.roundedBorder).frame(width: 200)
                        }
                        NumberField(label: "Vikt", value: $model.profile.weightKg, unit: "kg", range: 30...200, step: 0.5)
                        NumberField(label: "Längd", value: $model.profile.heightCm, unit: "cm", range: 120...230, step: 1)
                        NumberField(label: "FTP", value: $model.profile.ftp, unit: "W", range: 50...600, step: 1)
                        NumberField(label: "Cykelns vikt", value: $model.profile.bikeWeightKg, unit: "kg", range: 4...30, step: 0.1)
                        LabeledField("Maxpuls") {
                            TextField("valfritt", value: $model.profile.maxHeartRate, format: .number)
                                .textFieldStyle(.roundedBorder).frame(width: 80)
                            Text("bpm").foregroundStyle(Theme.textSecondary)
                        }
                        Text("Vet du inte din FTP? Kör FTP-ramptestet under Träningspass.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Tröja")
                        HStack(spacing: 10) {
                            ForEach(RiderProfile.jerseyPalette.indices, id: \.self) { i in
                                Circle()
                                    .fill(Theme.jersey(i))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: model.profile.jerseyColorIndex == i ? 3 : 0))
                                    .onTapGesture { model.profile.jerseyColorIndex = i }
                            }
                        }
                        SectionTitle("Åkning").padding(.top, 8)
                        Toggle("ERG-läge i träningspass", isOn: $model.settings.ergEnabled)
                        Toggle("Autopaus när du slutar trampa", isOn: $model.settings.autoPause)
                        Toggle("Visa namn ovanför medcyklister", isOn: $model.settings.showRiderNames)
                        Picker("Standardkamera", selection: $model.settings.cameraMode) {
                            ForEach(CameraMode.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(width: 280)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Trainerkänsla")
                                Slider(value: $model.settings.trainerDifficulty, in: 0...1, step: 0.05)
                                Text("\(Int(model.settings.trainerDifficulty * 100)) %").monospacedDigit().frame(width: 44)
                            }
                            Text("Andel av backens lutning som trainern återger. 100 % = som på riktigt. Påverkar inte farten i spelet.")
                                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Dina zoner")
                    HStack(spacing: 8) {
                        ForEach(PowerZone.allCases, id: \.self) { z in
                            let bounds = zoneBounds(z)
                            VStack(alignment: .leading, spacing: 4) {
                                Capsule().fill(Theme.zoneColor(z)).frame(height: 6)
                                Text("Z\(z.rawValue) \(z.name)").font(.system(size: 11, weight: .bold))
                                Text(bounds).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func zoneBounds(_ z: PowerZone) -> String {
        let ftp = model.profile.ftp
        let edges = [0, 0.55, 0.76, 0.91, 1.06, 1.21, 1.51]
        let i = z.rawValue - 1
        let lo = Int((edges[i] * ftp).rounded())
        if i == edges.count - 1 { return "\(lo)+ W" }
        return "\(lo)–\(Int((edges[i + 1] * ftp).rounded()) - 1) W"
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            content
        }
    }
}

private struct NumberField: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledField(label) {
            TextField(label, value: $value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            Stepper("", value: $value, in: range, step: step).labelsHidden()
            Text(unit).foregroundStyle(Theme.textSecondary)
        }
    }
}
