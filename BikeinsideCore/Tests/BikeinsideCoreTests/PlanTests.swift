import Foundation
import Testing
@testable import BikeinsideCore

@Suite struct PlanTests {
    let cal = Calendar.swedish

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    @Test func plansReferenceRealWorkouts() {
        for p in TrainingPlan.all {
            for w in p.weeks { for s in w {
                #expect(WorkoutLibrary.workout(id: s.workoutId) != nil, "\(p.id) uses unknown \(s.workoutId)")
                #expect((0...6).contains(s.weekday))
            } }
        }
    }

    @Test func scheduleStartsOnMondayAndTracksCompletion() {
        // Wednesday 2026-12-02 → plan starts Monday 2026-11-30
        let plan = TrainingPlan.getStarted
        let sched = plan.schedule(start: date("2026-12-02 10:00"), completed: [
            (date("2026-11-30 18:00"), "recovery-30"),     // week 1 Monday – done on the day
            (date("2026-12-03 07:00"), "endurance-60"),    // week 1 Wednesday's session done a day late
            (date("2026-12-07 12:00"), "endurance-60"),    // week 2 Monday
        ], calendar: cal)
        #expect(sched.count == 9)
        #expect(cal.component(.weekday, from: sched[0].date) == 2, "Monday")
        #expect(sched[0].done && sched[1].done && !sched[2].done)
        let week3first = sched.first { $0.week == 2 }!
        #expect(!week3first.done)
        #expect(sched.filter(\.done).count == 3)
    }

    @Test func trainingLoadConverges() {
        let start = date("2026-01-01 12:00")
        let rides = (0..<120).map { (cal.date(byAdding: .day, value: $0, to: start)!, 60.0) }
        let s = TrainingLoad.series(rides: rides, until: cal.date(byAdding: .day, value: 119, to: start)!, calendar: cal)
        #expect(s.count == 120)
        #expect(abs(s.last!.fitness - 60) < 4 && abs(s.last!.fatigue - 60) < 0.5)
        // a rest week drops fatigue faster than fitness → positive form
        let rest = TrainingLoad.series(rides: rides, until: cal.date(byAdding: .day, value: 126, to: start)!, calendar: cal)
        #expect(rest.last!.form > 10)
        #expect(TrainingLoad.series(rides: [], until: start).isEmpty)
    }

    @Test func powerCurveTakesBestPerDuration() {
        var a = RideStats(); a.bestEfforts = [BestEffort(seconds: 5, watts: 800), BestEffort(seconds: 60, watts: 400)]
        var b = RideStats(); b.bestEfforts = [BestEffort(seconds: 5, watts: 700), BestEffort(seconds: 60, watts: 450), BestEffort(seconds: 1200, watts: 260)]
        let curve = TrainingLoad.powerCurve([a, b])
        #expect(curve.map(\.watts) == [800, 450, 260])
    }
}
