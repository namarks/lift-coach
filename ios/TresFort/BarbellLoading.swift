import Foundation

struct PlateCount: Equatable, Identifiable {
    let weight: Double
    let count: Int
    var id: Double { weight }
}

struct PlateBreakdown: Equatable {
    let perSide: [PlateCount]
    let achievableWeight: Double
    let remainingWeight: Double
}

struct WarmupStep: Equatable, Identifiable {
    let id: Int
    var weight: Double
    var reps: Int
}

enum BarbellLoading {
    /// Standard lb plates, unlimited pairs. Show the unfilled remainder instead
    /// of silently recommending a load heavier than the member chose.
    static func breakdown(target: Double, bar: Double = 45) -> PlateBreakdown? {
        guard target.isFinite, bar.isFinite, bar > 0, target >= bar, target <= 10_000 else { return nil }
        var remainder = (target - bar) / 2
        var plates: [PlateCount] = []
        for plate in [45.0, 35, 25, 10, 5, 2.5] {
            let count = Int((remainder / plate).rounded(.down))
            if count > 0 { plates.append(PlateCount(weight: plate, count: count)) }
            remainder -= Double(count) * plate
        }
        return PlateBreakdown(perSide: plates, achievableWeight: target - remainder * 2,
                              remainingWeight: remainder * 2)
    }

    static func warmup(target: Double, bar: Double = 45) -> [WarmupStep] {
        guard breakdown(target: target, bar: bar) != nil else { return [] }
        if target == bar { return [WarmupStep(id: 0, weight: bar, reps: 8)] }
        let loads = [bar, max(bar, bar + ((target * 0.5 - bar) / 5).rounded(.down) * 5),
                     max(bar, bar + ((target * 0.75 - bar) / 5).rounded(.down) * 5)]
        var steps: [WarmupStep] = []
        for (index, load) in loads.enumerated() where steps.last?.weight != load {
            steps.append(WarmupStep(id: index, weight: min(target, load), reps: [8, 5, 3][index]))
        }
        return steps
    }
}
