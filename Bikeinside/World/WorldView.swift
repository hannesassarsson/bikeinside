import AppKit
import SceneKit
import SwiftUI

/// SCNView that leaves keyboard focus to SwiftUI.
final class RideSCNView: SCNView {
    override var acceptsFirstResponder: Bool { false }
}

/// Hosts the SceneKit world and drives the ride loop from the display's refresh.
struct WorldView: NSViewRepresentable {
    let controller: RideController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> RideSCNView {
        let v = RideSCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 120
        v.rendersContinuously = true
        v.isPlaying = true
        v.allowsCameraControl = false
        v.backgroundColor = .black
        context.coordinator.attach(to: v)
        return v
    }

    func updateNSView(_ nsView: RideSCNView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: RideSCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        let controller: RideController
        private var link: CADisplayLink?
        private var last: CFTimeInterval?
        private weak var view: SCNView?

        init(controller: RideController) { self.controller = controller }

        func attach(to v: SCNView) {
            view = v
            if let world = controller.world, v.scene !== world.scene {
                v.scene = world.scene
                v.pointOfView = world.cameraNode
            }
            if link == nil {
                let l = v.displayLink(target: self, selector: #selector(step(_:)))
                l.add(to: .main, forMode: .common)
                link = l
            }
        }

        @objc func step(_ link: CADisplayLink) {
            let now = link.timestamp
            let dt = last.map { now - $0 } ?? 0
            last = now
            if let v = view, let world = controller.world, v.scene !== world.scene {
                v.scene = world.scene
                v.pointOfView = world.cameraNode
            }
            controller.frame(dt: dt)
        }

        func stop() {
            link?.invalidate()
            link = nil
        }
    }
}
