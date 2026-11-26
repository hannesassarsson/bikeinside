import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct WorldTests {
    @Test func primitivesFaceOutwards() {
        var m = Mesh()
        Primitives.blob(into: &m, center: Float3(), radius: Float3(1, 1, 1), color: Float3(1, 1, 1))
        Primitives.box(into: &m, min: Float3(-1, -1, -1), max: Float3(1, 1, 1), color: Float3(1, 1, 1), bottom: true)
        Primitives.frustum(into: &m, center: Float3(0, -1, 0), bottomRadius: 1, topRadius: 0.5, height: 2, sides: 8, color: Float3(1, 1, 1))
        for t in 0..<m.triangleCount {
            let a = m.positions[Int(m.indices[3 * t])], b = m.positions[Int(m.indices[3 * t + 1])], c = m.positions[Int(m.indices[3 * t + 2])]
            let centroid = (a + b + c) / 3
            let n = Mesh.faceNormal(a, b, c)
            #expect((n * centroid).sum() > 0, "triangle \(t) faces inwards")
        }
    }

    @Test func appendTransformsAndKeepsNormalsUnit() {
        var src = Mesh()
        Primitives.box(into: &src, min: Float3(0, 0, 0), max: Float3(1, 1, 1), color: Float3(1, 0, 0))
        var dst = Mesh()
        dst.append(src, transform: MeshTransform(translation: Float3(10, 0, 0), yaw: .pi / 2, scale: Float3(2, 1, 3)))
        #expect(dst.vertexCount == src.vertexCount)
        for n in dst.normals { #expect(abs((n * n).sum() - 1) < 1e-4) }
        // yaw +90°: local +X → world -Z
        let b = dst.bounds
        #expect(b.max.z <= 0.0001 && b.min.z >= -2.0001)
        #expect(abs(b.min.x - 10) < 1e-4 && abs(b.max.x - 13) < 1e-4)
    }

    @Test func prototypeBudgets() {
        // keep vertex counts small – these are instanced tens of thousands of times
        #expect(Primitives.spruce(detail: true).vertexCount <= 80)
        #expect(Primitives.pine(detail: true).vertexCount <= 90)
        #expect(Primitives.birch(detail: true).vertexCount <= 130)
        #expect(Primitives.spruce(detail: false).vertexCount <= 30)
    }

    @Test(arguments: RouteLibrary.all.map(\.id))
    func worldIsConsistent(id: String) throws {
        let route = RouteBuilder.build(try #require(RouteLibrary.blueprint(id: id)))
        let t0 = Date()
        let world = WorldBuilder.build(route: route)
        let elapsed = Date().timeIntervalSince(t0)
        let sceneryVerts = world.sceneryChunks.reduce(0) { $0 + $1.mesh.vertexCount }
        let terrainVerts = world.terrainChunks.reduce(0) { $0 + $1.mesh.vertexCount }
        print("[world] \(route.name): \(String(format: "%.2f", elapsed)) s, grid \(world.terrain.cols)x\(world.terrain.rows), trees \(world.stats.trees), rocks \(world.stats.rocks), houses \(world.stats.houses), tris \(world.stats.triangles), terrainVerts \(terrainVerts), sceneryVerts \(sceneryVerts), chunks \(world.terrainChunks.count)/\(world.sceneryChunks.count)")

        let terrain = world.terrain
        // Road bed sits just below the road everywhere along the route.
        for i in stride(from: 0, to: route.points.count, by: 25) {
            let p = route.points[i]
            let h = terrain.height(x: p.x, z: p.z)
            #expect(h < p.y + 0.05, "terrain pokes through road at \(i)")
            #expect(h > p.y - 1.5, "road floating at \(i)")
            // and at the road edges
            let right = Vec2(-route.headings[i].y, route.headings[i].x)
            for side in [-1.0, 1.0] {
                let e = p.xz + right * (side * Terrain.roadHalfWidth)
                #expect(terrain.height(x: e.x, z: e.y) < p.y + 0.06, "terrain above road edge at \(i)")
            }
        }
        // distance field: nodes near the road are close, exact refinement agrees
        for i in stride(from: 0, to: route.points.count, by: 301) {
            let p = route.points[i]
            #expect(terrain.roadDistance(x: p.x, z: p.z, route: route) < 0.01)
            #expect(terrain.roadDistance(x: p.x, z: p.z) < terrain.cellSize)
        }
        if route.theme == .lake, let w = route.waterLevel {
            let underwater = terrain.heights.filter { Double($0) < w - 1 }.count
            #expect(Double(underwater) / Double(terrain.heights.count) > 0.15, "lake missing")
            #expect(terrain.insideLoop.contains(true))
        }
        #expect(world.stats.trees > 2000)
        #expect(world.stats.houses > 5)
        #expect(sceneryVerts < 3_000_000, "scenery too heavy")
        #expect(!world.road.isEmpty && !world.arches.isEmpty)
        // all indices in range
        for chunk in world.terrainChunks + world.sceneryChunks {
            #expect(chunk.mesh.indices.allSatisfy { Int($0) < chunk.mesh.vertexCount })
            #expect(chunk.mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
        // road faces up
        for k in stride(from: 0, to: world.road.indices.count, by: 3 * 50) {
            let a = world.road.positions[Int(world.road.indices[k])]
            let b = world.road.positions[Int(world.road.indices[k + 1])]
            let c = world.road.positions[Int(world.road.indices[k + 2])]
            #expect(Mesh.faceNormal(a, b, c).y > 0.5)
        }
    }
}

@Suite struct LegIKTests {
    @Test func kneeKeepsBoneLengthsAndBendsForward() {
        let hip = Vec2(-0.17, 0.93)
        for k in 0..<36 {
            let a = Double(k) / 36 * 2 * .pi
            let foot = LegIK.pedal(bottomBracket: Vec2(0, 0.3), crankLength: 0.17, angle: a)
            let knee = LegIK.knee(hip: hip, foot: foot, upper: 0.44, lower: 0.43)
            #expect(abs((knee - hip).length - 0.44) < 1e-6)
            #expect(abs((foot - knee).length - 0.43) < 1e-6)
            #expect(knee.x > hip.x)
        }
    }

    @Test func outOfReachStraightens() {
        let knee = LegIK.knee(hip: Vec2(0, 1), foot: Vec2(0, -5), upper: 0.5, lower: 0.5)
        #expect(abs(knee.x) < 1e-3 && abs(knee.y - 0.5) < 1e-3)
    }
}
