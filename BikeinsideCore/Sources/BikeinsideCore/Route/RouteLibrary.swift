import Foundation

/// The built-in worlds. Each is an original route through procedurally
/// generated Swedish landscape.
public enum RouteLibrary {
    public static let all: [RouteBlueprint] = [skogsslingan, sjorundan, fjallvagen, skargardsvagen, grusvagen, milrundan]

    /// Suffix marking the reversed version of a route.
    public static let reversedSuffix = "-rev"

    /// Looks up a route; ids ending in `-rev` give the route ridden the other way.
    public static func blueprint(id: String) -> RouteBlueprint? {
        if id.hasSuffix(reversedSuffix) {
            return blueprint(id: String(id.dropLast(reversedSuffix.count)))?.reversed()
        }
        return all.first { $0.id == id }
    }

    // MARK: Skogsslingan – rolling forest loop

    public static let skogsslingan = RouteBlueprint(
        id: "skogsslingan",
        name: "Skogsslingan",
        summary: "Kuperad runda genom granskog och björkhagar. Korta backar, perfekt för uppvärmning och fri cykling.",
        theme: .forest,
        seed: 0x5C06_5117,
        controlPoints: [
            Vec2(0, 0), Vec2(600, -150), Vec2(1200, -60), Vec2(1700, 280), Vec2(1900, 900),
            Vec2(1720, 1500), Vec2(1250, 1800), Vec2(700, 1700), Vec2(320, 2000), Vec2(-300, 1920),
            Vec2(-720, 1500), Vec2(-820, 900), Vec2(-520, 500), Vec2(-460, 150),
        ],
        elevation: [
            .init(0.00, 40), .init(0.08, 58), .init(0.15, 46), .init(0.23, 80), .init(0.30, 70),
            .init(0.38, 48), .init(0.45, 60), .init(0.53, 96), .init(0.59, 108), .init(0.66, 80),
            .init(0.73, 62), .init(0.80, 74), .init(0.88, 50), .init(0.95, 42),
        ],
        climbNames: ["Granbacken", "Tallåsen", "Björkkullen"],
        sprints: [.init(name: "Hagsprinten", startFraction: 0.40, lengthMeters: 300)]
    )

    // MARK: Sjörundan – flat lake loop

    public static let sjorundan: RouteBlueprint = {
        var pts: [Vec2] = []
        let count = 20
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi
            let r = 1.0 + 0.09 * sin(3 * a + 0.4) + 0.05 * cos(5 * a)
            pts.append(Vec2(cos(a) * 2150 * r, sin(a) * 1650 * r))
        }
        return RouteBlueprint(
            id: "sjorundan",
            name: "Sjörundan",
            summary: "Platt och snabb runda längs en stor insjö. Bra för intervaller, tempo och att åka i klunga.",
            theme: .lake,
            seed: 0x5_7055,
            controlPoints: pts,
            elevation: [
                .init(0.00, 14), .init(0.10, 18), .init(0.20, 12), .init(0.32, 22), .init(0.42, 16),
                .init(0.60, 13), .init(0.66, 36), .init(0.76, 18), .init(0.88, 12),
            ],
            climbNames: ["Strandbrinken"],
            sprints: [
                .init(name: "Bryggsprinten", startFraction: 0.12, lengthMeters: 400),
                .init(name: "Vasssprinten", startFraction: 0.80, lengthMeters: 400),
            ],
            waterLevel: 5
        )
    }()

    // MARK: Fjällvägen – mountain loop with one long climb

    public static let fjallvagen = RouteBlueprint(
        id: "fjallvagen",
        name: "Fjällvägen",
        summary: "En lång stigning upp mot kalfjället följd av en snabb utförskörning genom dalen. För dig som gillar backar.",
        theme: .mountain,
        seed: 0xF1A11,
        controlPoints: [
            Vec2(0, 0), Vec2(800, 220), Vec2(1550, 650), Vec2(2250, 1300), Vec2(2700, 2100),
            Vec2(2620, 2800), Vec2(2120, 3120), Vec2(1600, 2850), Vec2(1320, 2250), Vec2(900, 1650),
            Vec2(320, 1240), Vec2(-280, 820), Vec2(-420, 320),
        ],
        elevation: [
            .init(0.00, 300), .init(0.05, 304), .init(0.15, 352), .init(0.25, 412), .init(0.35, 478),
            .init(0.45, 548), .init(0.50, 556), .init(0.55, 545), .init(0.65, 470), .init(0.75, 392),
            .init(0.85, 326), .init(0.93, 302),
        ],
        climbNames: ["Fjällbacken"],
        sprints: [.init(name: "Dalsprinten", startFraction: 0.88, lengthMeters: 350)],
        waterLevel: 280
    )

    // MARK: Skärgårdsvägen – island loop in the archipelago

    public static let skargardsvagen: RouteBlueprint = {
        var pts: [Vec2] = []
        let count = 22
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi
            // coves and headlands
            let r = 1.0 + 0.12 * sin(4 * a + 1.1) + 0.07 * cos(7 * a + 0.3) + 0.05 * sin(2 * a)
            pts.append(Vec2(cos(a) * 1750 * r, sin(a) * 1350 * r))
        }
        return RouteBlueprint(
            id: "skargardsvagen",
            name: "Skärgårdsvägen",
            summary: "Runt en klippö i skärgården. Granithällar, tallar, sjöbodar och havet på ena sidan hela vägen. Korta, vassa backar.",
            theme: .coast,
            seed: 0x5CA6_A2D,
            controlPoints: pts,
            elevation: [
                .init(0.00, 6), .init(0.06, 8), .init(0.095, 28), .init(0.13, 10), .init(0.22, 8),
                .init(0.26, 38), .init(0.30, 41), .init(0.34, 12), .init(0.45, 6), .init(0.56, 9),
                .init(0.60, 36), .init(0.64, 43), .init(0.69, 14), .init(0.78, 7), .init(0.86, 25), .init(0.90, 8),
            ],
            climbNames: ["Klippbacken", "Utsiktsberget", "Fyrbacken"],
            sprints: [.init(name: "Hamnsprinten", startFraction: 0.38, lengthMeters: 350)],
            waterLevel: 0
        )
    }()

    // MARK: Grusvägen – gravel through the forest

    public static let grusvagen = RouteBlueprint(
        id: "grusvagen",
        name: "Grusvägen",
        summary: "Grusväg genom djup barrskog. Tyngre rullmotstånd, långa sega backar och ingen trafik – perfekt för distanspass.",
        theme: .forest,
        seed: 0x6A05,
        controlPoints: [
            Vec2(0, 0), Vec2(700, 120), Vec2(1300, -40), Vec2(1900, 260), Vec2(2250, 850),
            Vec2(2050, 1450), Vec2(1500, 1700), Vec2(900, 1550), Vec2(450, 1850), Vec2(-150, 1600),
            Vec2(-450, 1000), Vec2(-300, 450),
        ],
        elevation: [
            .init(0.00, 180), .init(0.10, 196), .init(0.20, 228), .init(0.28, 236), .init(0.36, 210),
            .init(0.46, 200), .init(0.56, 246), .init(0.64, 262), .init(0.72, 238), .init(0.82, 205),
            .init(0.92, 186),
        ],
        climbNames: ["Kolarbacken", "Tjärnåsen"],
        sprints: [.init(name: "Myrsprinten", startFraction: 0.44, lengthMeters: 300)],
        surface: .gravel
    )

    // MARK: Milrundan – the long one (2.2 mil around a big lake)

    public static let milrundan: RouteBlueprint = {
        var pts: [Vec2] = []
        let count = 28
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi
            let r = 1.0 + 0.10 * sin(3 * a + 0.7) + 0.06 * cos(5 * a + 1.9) + 0.04 * sin(9 * a)
            pts.append(Vec2(cos(a) * 4100 * r, sin(a) * 2500 * r))
        }
        return RouteBlueprint(
            id: "milrundan",
            name: "Milrundan",
            summary: "Den långa: drygt två mil runt en stor sjö med tre riktiga backar, byar och raksträckor. För långpass och grupplopp.",
            theme: .lake,
            seed: 0x31_1A,
            controlPoints: pts,
            elevation: [
                .init(0.00, 22), .init(0.10, 24), .init(0.135, 62), .init(0.15, 68), .init(0.20, 30),
                .init(0.34, 18), .init(0.45, 24), .init(0.49, 80), .init(0.51, 86), .init(0.58, 40),
                .init(0.68, 20), .init(0.78, 26), .init(0.815, 60), .init(0.83, 64), .init(0.90, 26),
            ],
            climbNames: ["Byabacken", "Åsen", "Kyrkbacken"],
            sprints: [
                .init(name: "Bysprinten", startFraction: 0.30, lengthMeters: 400),
                .init(name: "Strandsprinten", startFraction: 0.72, lengthMeters: 400),
            ],
            waterLevel: 6
        )
    }()
}

extension RouteBlueprint {
    /// The same road ridden in the opposite direction.
    public func reversed() -> RouteBlueprint {
        var bp = self
        bp.id = id + RouteLibrary.reversedSuffix
        bp.name = name + " baklänges"
        // keep the same start point, walk the rest backwards
        bp.controlPoints = [controlPoints[0]] + controlPoints.dropFirst().reversed()
        // Elevation key at t maps to 1 - t; keep the start point (t = 0) fixed.
        bp.elevation = elevation.map { ElevationKey($0.t == 0 ? 0 : 1 - $0.t, $0.elevation) }.sorted { $0.t < $1.t }
        bp.climbNames = climbNames.reversed().map { $0 + " (bakvägen)" }
        bp.sprints = sprints.map { SprintSpec(name: $0.name, startFraction: max(0, 1 - $0.startFraction - 0.05), lengthMeters: $0.lengthMeters) }
        return bp
    }
}
