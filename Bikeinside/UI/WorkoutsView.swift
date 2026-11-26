import BikeinsideCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutsView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Träningspass").font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("Alla pass anpassas efter din FTP (\(Int(model.profile.ftp)) W). I ERG-läge styr trainern effekten åt dig.")
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    importing = true
                } label: {
                    Label("Importera .erg/.mrc", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
            }

            ForEach(Workout.Category.allCases, id: \.self) { cat in
                let items = model.allWorkouts.filter { $0.category == cat }
                if !items.isEmpty {
                    SectionTitle(cat.displayName)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(items) { w in
                            WorkoutCard(workout: w, ftp: model.profile.ftp, selected: model.selectedWorkoutId == w.id,
                                        onRemove: cat == .custom ? { model.removeImportedWorkout(w) } : nil)
                                .onTapGesture {
                                    model.selectedWorkoutId = w.id
                                    model.section = .ride
                                }
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "erg") ?? .plainText, UTType(filenameExtension: "mrc") ?? .plainText, .plainText]) { result in
            switch result {
            case .success(let url):
                do {
                    let w = try model.importWorkout(from: url)
                    importError = nil
                    model.selectedWorkoutId = w.id
                } catch {
                    importError = "Kunde inte läsa filen. Stöds: .erg (watt) och .mrc (% av FTP)."
                }
            case .failure:
                importError = "Importen avbröts."
            }
        }
    }
}

struct WorkoutCard: View {
    let workout: Workout
    let ftp: Double
    let selected: Bool
    var onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.name).font(.system(size: 16, weight: .bold))
                    Text("\(Format.duration(workout.duration)) · TSS \(Int(workout.estimatedTSS(ftp: ftp)))\(workout.test != nil ? " · Test" : "")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Ta bort importerat pass")
                }
            }
            WorkoutChart(workout: workout, ftp: ftp).frame(height: 56)
            Text(workout.summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3, reservesSpace: true)
        }
        .padding(14)
        .background(selected ? Theme.panelHighlight : Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Theme.accent : .white.opacity(0.06), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }
}
