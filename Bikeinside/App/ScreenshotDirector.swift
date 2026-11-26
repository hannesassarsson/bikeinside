import AppKit
import BikeinsideCore
import SwiftUI

/// Automated tour used by CI to produce screenshots of the real app.
/// Only active when the `BIKEINSIDE_SCREENSHOTS` environment variable points
/// at an output directory; otherwise it does nothing.
@MainActor
final class ScreenshotDirector {
    private let model: AppModel
    private let dir: URL
    private var window: NSWindow? { NSApp.windows.first { $0.isVisible && $0.contentView != nil } }

    private static var started = false

    static func startIfRequested(model: AppModel) {
        guard !started, let path = ProcessInfo.processInfo.environment["BIKEINSIDE_SCREENSHOTS"] else { return }
        started = true
        let d = ScreenshotDirector(model: model, dir: URL(fileURLWithPath: path))
        Task { await d.run() }
    }

    private init(model: AppModel, dir: URL) {
        self.model = model
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(("[screenshots] " + s + "\n").data(using: .utf8)!)
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private func run() async {
        model.hasCompletedOnboarding = true
        model.profile.name = "Hannes"
        model.profile.ftp = 250
        model.profile.weightKg = 75
        await wait(1.5)
        if let w = window {
            w.setContentSize(NSSize(width: 1440, height: 900))
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        await wait(1.0)

        model.screen = .home
        for (name, section) in [("01-start", AppModel.Section.ride), ("02-pass", .workouts), ("03-enheter", .devices), ("04-profil", .profile)] {
            model.section = section
            await wait(1.2)
            capture(name)
        }

        // Rides in each world
        model.settings.paceGroup = .tempo
        let tours: [(route: String, workout: String?, camera: CameraMode, untilClimb: Bool)] = [
            ("skogsslingan", nil, .chase, false),
            ("sjorundan", WorkoutLibrary.sweetSpot3x10.id, .close, false),
            ("fjallvagen", nil, .chase, true),
        ]
        var lastController: RideController?
        for (i, tour) in tours.enumerated() {
            model.selectedRouteId = tour.route
            model.selectedWorkoutId = tour.workout
            model.settings.cameraMode = tour.camera
            model.startRide()
            guard case .ride(let c) = model.screen else { continue }
            var waited = 0.0
            while !c.isLoaded && waited < 120 {
                await wait(0.5)
                waited += 0.5
            }
            log("world \(tour.route) loaded after \(waited) s")
            c.virtualFollowsTarget = tour.workout != nil
            c.virtualPower = 245
            // Fast-forward the simulation so riders spread out and we're somewhere interesting.
            let target = tour.untilClimb ? 1800.0 : 600.0
            var steps = 0
            while steps < 20_000 {
                c.frame(dt: 0.1)
                steps += 1
                if Double(steps) * 0.1 > 60, tour.untilClimb, c.engine.activeSegment?.segment.kind == .climb,
                   c.engine.activeSegment!.progress > 0.35 { break }
                if !tour.untilClimb, Double(steps) * 0.1 >= target { break }
            }
            await wait(2.5) // let real frames render and HUD/camera settle
            capture(String(format: "%02d-cykla-%@", 5 + i, tour.route), scene: c)
            if i == 0 {
                c.cameraMode = .side
                await wait(1.5)
                capture("08-cykla-sidovy", scene: c)
                c.cameraMode = .drone
                await wait(2.0)
                capture("09-cykla-dronare", scene: c)
            }
            lastController = c
            if i < tours.count - 1 {
                c.finish(save: false)
                await wait(0.8)
            }
        }

        // Summary of the last ride (fast-forward a bit more so there's data)
        if let c = lastController {
            for _ in 0..<6000 { c.frame(dt: 0.1) }
            c.finish(save: true)
            await wait(1.5)
            capture("10-sammanfattning")
            model.closeSummary()
            await wait(1.2)
            capture("11-historik")
        }
        log("done")
        NSApp.terminate(nil)
    }

    /// Captures the window with the system tool (includes Metal content and
    /// materials) and, for rides, also an offscreen SceneKit render as fallback.
    private func capture(_ name: String, scene controller: RideController? = nil) {
        guard let w = window else { log("no window for \(name)"); return }
        let out = dir.appendingPathComponent("\(name).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l\(w.windowNumber)", out.path]
        do {
            try p.run()
            p.waitUntilExit()
            log("captured \(name) status \(p.terminationStatus)")
        } catch {
            log("screencapture failed: \(error)")
        }
        // Fallback: whole content view drawn by AppKit.
        if let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: dir.appendingPathComponent("\(name)-appkit.png"))
            }
        }
    }
}
