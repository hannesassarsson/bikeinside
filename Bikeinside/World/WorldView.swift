import RealityKit
import SwiftUI

/// Hosts the RealityKit world and drives the ride loop from RealityKit's frame updates.
struct WorldView: View {
    let controller: RideController
    @State private var subscription: EventSubscription?

    var body: some View {
        RealityView { content in
            guard let world = controller.world else { return }
            content.add(world.root)
            subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                let dt = event.deltaTime
                MainActor.assumeIsolated {
                    controller.frame(dt: dt)
                }
            }
        }
        .background(Color.black)
    }
}
