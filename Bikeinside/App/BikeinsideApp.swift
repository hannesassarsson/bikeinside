import SwiftUI

@main
struct BikeinsideApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Bikeinside") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Cykling") {
                Button("Starta åkning") { model.startRide() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isRiding)
                Button("Pausa / fortsätt") {
                    if case .ride(let c) = model.screen { c.togglePause() }
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!model.isRiding)
                Button("Avsluta åkning") {
                    if case .ride(let c) = model.screen { c.requestEnd() }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.isRiding)
                Divider()
                Button("Sök efter enheter") { model.bluetooth.startScan() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.screen {
            case .home:
                HomeView()
                    .transition(.opacity)
            case .ride(let controller):
                RideView(controller: controller)
                    .transition(.opacity)
            case .summary(let record, let isNew, let update):
                SummaryView(record: record, isNew: isNew, update: update)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screenKey)
        .task {
            model.refreshHealth()
            ScreenshotDirector.startIfRequested(model: model)
        }
        .sheet(isPresented: Binding(
            get: { !model.hasCompletedOnboarding },
            set: { if !$0 { model.hasCompletedOnboarding = true } })
        ) {
            OnboardingView()
        }
    }

    private var screenKey: Int {
        switch model.screen {
        case .home: return 0
        case .ride: return 1
        case .summary: return 2
        }
    }
}
