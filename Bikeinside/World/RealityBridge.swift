import BikeinsideCore
import Metal
import RealityKit
import simd

enum RenderError: LocalizedError {
    case noMetal
    case noShaders

    var errorDescription: String? {
        switch self {
        case .noMetal: return "Den här datorn saknar Metal-stöd."
        case .noShaders: return "Kunde inte ladda appens shaders."
        }
    }
}

extension Mesh {
    /// Uploads to a RealityKit mesh: position, normal and vertex colour (RGBA8).
    @MainActor
    func meshResource() throws -> MeshResource {
        let n = positions.count
        let stride = 28
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0),
            LowLevelMesh.Attribute(semantic: .normal, format: .float3, offset: 12),
            LowLevelMesh.Attribute(semantic: .color, format: .uchar4Normalized, offset: 24),
        ]
        desc.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: stride)]
        desc.vertexCapacity = n
        desc.indexCapacity = indices.count
        desc.indexType = .uint32
        let ll = try LowLevelMesh(descriptor: desc)
        let positions = self.positions, normals = self.normals, colors = self.colors
        ll.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            guard let base = raw.baseAddress else { return }
            func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
            for i in 0..<n {
                let o = i * stride
                let p = positions[i], q = normals[i], c = colors[i]
                base.storeBytes(of: p.x, toByteOffset: o, as: Float.self)
                base.storeBytes(of: p.y, toByteOffset: o + 4, as: Float.self)
                base.storeBytes(of: p.z, toByteOffset: o + 8, as: Float.self)
                base.storeBytes(of: q.x, toByteOffset: o + 12, as: Float.self)
                base.storeBytes(of: q.y, toByteOffset: o + 16, as: Float.self)
                base.storeBytes(of: q.z, toByteOffset: o + 20, as: Float.self)
                base.storeBytes(of: byte(c.x), toByteOffset: o + 24, as: UInt8.self)
                base.storeBytes(of: byte(c.y), toByteOffset: o + 25, as: UInt8.self)
                base.storeBytes(of: byte(c.z), toByteOffset: o + 26, as: UInt8.self)
                base.storeBytes(of: UInt8(255), toByteOffset: o + 27, as: UInt8.self)
            }
        }
        let indices = self.indices
        ll.withUnsafeMutableIndices { raw in
            indices.withUnsafeBytes { src in raw.copyMemory(from: src) }
        }
        let b = bounds
        ll.parts.replaceAll([
            LowLevelMesh.Part(indexOffset: 0, indexCount: indices.count, topology: .triangle, materialIndex: 0,
                              bounds: BoundingBox(min: b.min, max: b.max)),
        ])
        return try MeshResource(from: ll)
    }
}

/// Materials built from the Metal surface shaders in WorldShaders.metal.
@MainActor
struct WorldMaterials {
    let ground: CustomMaterial
    let water: CustomMaterial

    init(fogColor: SIMD3<Float>, fogEnd: Float) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetal }
        guard let library = device.makeDefaultLibrary() else { throw RenderError.noShaders }
        let fog = SIMD4<Float>(fogColor.x, fogColor.y, fogColor.z, fogEnd)
        var g = try CustomMaterial(surfaceShader: CustomMaterial.SurfaceShader(named: "bikeinsideSurface", in: library), lightingModel: .lit)
        g.custom.value = fog
        ground = g
        var w = try CustomMaterial(surfaceShader: CustomMaterial.SurfaceShader(named: "bikeinsideWater", in: library), lightingModel: .lit)
        w.custom.value = fog
        water = w
    }
}
