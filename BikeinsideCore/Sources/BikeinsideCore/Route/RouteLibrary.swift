import Foundation

/// The built-in worlds. Each is an original route through procedurally
/// generated Swedish landscape.
public enum RouteLibrary {
    public static let all: [RouteBlueprint] = [skogsslingan, sjorundan, fjallvagen]

    public static func blueprint(id: String) -> RouteBlueprint? {
        all.first { $0.id == id }
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
}
