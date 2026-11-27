import BikeinsideCore
import SwiftUI
import UniformTypeIdentifiers

/// Build your own structured workout: steps with duration, power (% of FTP,
/// optionally ramping) and cadence, plus an interval generator.
struct WorkoutEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let original: Workout?
    @State private var name = "Mitt pass"
    @State private var summary = ""
    @State private var steps: [EditableStep] = []
    @State private var reps = 5
    @State private var onSec = 180.0
    @State private var onPct = 110.0
    @State private var offSec = 120.0
    @State private var offPct = 55.0
    @State private var exporting = false

    struct EditableStep: Identifiable, Equatable {
        var id = UUID()
        var kind: WorkoutStep.Kind
        var label: String
        var seconds: Double
        var startPct: Double
        var endPct: Double
        var cadence: Int?

        var step: WorkoutStep {
            WorkoutStep(kind: kind, duration: max(seconds, 5), start: .ftp(startPct / 100), end: .ftp(endPct / 100),
                        cadence: cadence, label: label.isEmpty ? Self.defaultLabel(kind) : label)
        }

        static func defaultLabel(_ k: WorkoutStep.Kind) -> String {
            switch k {
            case .warmup: return "Uppvärmning"
            case .cooldown: return "Nedvarvning"
            case .recovery: return "Vila"
            case .free: return "Fritt"
            case .ramp: return "Ramp"
            case .work: return "Intervall"
            case .steady: return "Jämnt"
            }
        }

        init(kind: WorkoutStep.Kind, label: String = "", seconds: Double, startPct: Double, endPct: Double? = nil, cadence: Int? = nil) {
            self.kind = kind
            self.label = label
            self.seconds = seconds
            self.startPct = startPct
            self.endPct = endPct ?? startPct
            self.cadence = cadence
        }

        init(_ s: WorkoutStep, ftp: Double) {
            self.init(kind: s.kind, label: s.label, seconds: s.duration,
                      startPct: (s.start.fraction(ftp: ftp) * 100).rounded(), endPct: (s.end.fraction(ftp: ftp) * 100).rounded(), cadence: s.cadence)
        }
    }

    var workout: Workout {
        Workout(id: original?.id ?? "custom-\(UUID().uuidString.prefix(8).lowercased())", name: name.isEmpty ? "Mitt pass" : name,
                summary: summary.isEmpty ? "Eget pass" : summary, category: .custom, steps: steps.map(\.step))
    }

    var body: some View {
        let ftp = model.profile.ftp
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(original == nil ? "Skapa pass" : "Redigera pass").font(.system(size: 24, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(Format.duration(workout.duration)) · TSS \(Int(workout.estimatedTSS(ftp: ftp)))")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            HStack {
                TextField("Namn", text: $name).textFieldStyle(.roundedBorder).frame(width: 260)
                TextField("Beskrivning", text: $summary).textFieldStyle(.roundedBorder)
            }
            WorkoutChart(workout: workout, ftp: ftp).frame(height: 70)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Text("Lägg till:").font(.system(size: 12, weight: .semibold))
                Button("Uppvärmning") { steps.append(.init(kind: .warmup, seconds: 600, startPct: 45, endPct: 70)) }
                Button("Jämnt") { steps.append(.init(kind: .steady, seconds: 600, startPct: 75)) }
                Button("Intervall") { steps.append(.init(kind: .work, seconds: 300, startPct: 100)) }
                Button("Vila") { steps.append(.init(kind: .recovery, seconds: 180, startPct: 50)) }
                Button("Ramp") { steps.append(.init(kind: .ramp, seconds: 300, startPct: 70, endPct: 110)) }
                Button("Fritt") { steps.append(.init(kind: .free, seconds: 600, startPct: 100)) }
                Button("Nedvarvning") { steps.append(.init(kind: .cooldown, seconds: 300, startPct: 60, endPct: 40)) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .controlSize(.small)

            HStack(spacing: 8) {
                Text("Intervallgenerator:").font(.system(size: 12, weight: .semibold))
                Stepper("\(reps) ×", value: $reps, in: 1...30)
                durationField("på", $onSec)
                pctField($onPct)
                durationField("vila", $offSec)
                pctField($offPct)
                Button("Lägg till block") {
                    for k in 1...reps {
                        steps.append(.init(kind: .work, label: "Intervall \(k)/\(reps)", seconds: onSec, startPct: onPct))
                        steps.append(.init(kind: .recovery, seconds: offSec, startPct: offPct))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .font(.system(size: 12))

            List {
                ForEach($steps) { $s in
                    HStack(spacing: 10) {
                        Circle().fill(Theme.zoneColor(power: s.startPct / 100 * ftp, ftp: ftp)).frame(width: 10, height: 10)
                        Picker("", selection: $s.kind) {
                            ForEach([WorkoutStep.Kind.warmup, .steady, .work, .recovery, .ramp, .free, .cooldown], id: \.self) {
                                Text(EditableStep.defaultLabel($0)).tag($0)
                            }
                        }
                        .labelsHidden().frame(width: 130)
                        TextField("Etikett", text: $s.label).textFieldStyle(.roundedBorder).frame(width: 150)
                        durationField("", $s.seconds)
                        pctField($s.startPct)
                        Text("→").foregroundStyle(Theme.textSecondary)
                        pctField($s.endPct)
                        TextField("rpm", value: $s.cadence, format: .number).textFieldStyle(.roundedBorder).frame(width: 52)
                        Text("\(Int(s.startPct / 100 * ftp)) W").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.textSecondary).frame(width: 52)
                        Button { steps.removeAll { $0.id == s.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 240)

            HStack {
                Button("Exportera .mrc") { exporting = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(steps.isEmpty)
                Spacer()
                Button("Avbryt") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Spara") {
                    let w = workout
                    model.saveCustomWorkout(w)
                    model.selectedWorkoutId = w.id
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(steps.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 1000, height: 720)
        .onAppear {
            if let o = original {
                name = o.name
                summary = o.summary == "Eget pass" ? "" : o.summary
                steps = o.steps.map { EditableStep($0, ftp: ftp) }
            } else if steps.isEmpty {
                steps = [.init(kind: .warmup, seconds: 600, startPct: 45, endPct: 70), .init(kind: .cooldown, seconds: 300, startPct: 60, endPct: 40)]
            }
        }
        .fileExporter(isPresented: $exporting, document: TextDocument(text: WorkoutFileParser.mrc(workout, ftp: ftp)),
                      contentType: UTType(filenameExtension: "mrc") ?? .plainText, defaultFilename: "\(workout.name).mrc") { _ in }
    }

    private func durationField(_ label: String, _ v: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            if !label.isEmpty { Text(label) }
            TextField("min", value: Binding(get: { v.wrappedValue / 60 }, set: { v.wrappedValue = max(0.1, $0) * 60 }),
                      format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 56)
            Text("min").foregroundStyle(Theme.textSecondary)
        }
    }

    private func pctField(_ v: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            TextField("%", value: v, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder).frame(width: 50)
            Text("%").foregroundStyle(Theme.textSecondary)
        }
    }
}

struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
