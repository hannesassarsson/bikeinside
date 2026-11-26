import BikeinsideCore
import SceneKit
import simd

extension Mesh {
    /// Converts to an SCNGeometry with position/normal/colour sources (packed floats).
    func scnGeometry(material: SCNMaterial) -> SCNGeometry {
        func packed(_ v: [Float3]) -> Data {
            var flat = [Float]()
            flat.reserveCapacity(v.count * 3)
            for p in v { flat.append(p.x); flat.append(p.y); flat.append(p.z) }
            return flat.withUnsafeBufferPointer { Data(buffer: $0) }
        }
        let n = positions.count
        func source(_ data: Data, _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
            SCNGeometrySource(
                data: data, semantic: semantic, vectorCount: n, usesFloatComponents: true,
                componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3)
        }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles, primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size)
        let g = SCNGeometry(
            sources: [source(packed(positions), .vertex), source(packed(normals), .normal), source(packed(colors), .color)],
            elements: [element])
        g.materials = [material]
        return g
    }
}

enum Materials {
    /// Matte material that takes its colour from the vertex colours.
    static func vertexColored(roughness: CGFloat = 0.9, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        m.isDoubleSided = doubleSided
        return m
    }

    static func solid(_ color: NSColor, roughness: CGFloat = 0.6, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }
}

/// Places a node holding a Y-axis aligned primitive (cylinder/capsule) so it spans a → b.
func align(_ node: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>) {
    let d = b - a
    let len = (d * d).sum().squareRoot()
    node.simdPosition = (a + b) / 2
    guard len > 1e-5 else { return }
    node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: d / len)
}
