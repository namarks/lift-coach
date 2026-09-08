import ActivityKit
import Foundation

// App-side controller. Local Live Activity: we only ever set an endDate and
// let the system render the countdown — no APNs / push token in v1.
enum RestLiveActivity {
    private static var current: Activity<RestActivityAttributes>?

    static func start(exercise: String, endDate: Date, upNext: String, timerKind: String = "rest", controlID: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endNow()
        let attributes = RestActivityAttributes(exercise: exercise)
        let state = RestActivityAttributes.ContentState(endDate: endDate, upNext: upNext, timerKind: timerKind, controlID: controlID)
        current = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: endDate.addingTimeInterval(120)))
    }

    static func update(endDate: Date, upNext: String) {
        guard let activity = current else { return }
        var state = activity.content.state
        state.endDate = endDate
        state.upNext = upNext
        Task { await activity.update(.init(state: state, staleDate: endDate.addingTimeInterval(120))) }
    }

    static func endNow() {
        guard let activity = current else { return }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// ActivityKit restores active records independently of our process. End
    /// every orphan before launch recovery so a rest countdown left by an app
    /// kill cannot remain on the Lock Screen beside the recovered runner.
    static func endStaleActivities() async {
        current = nil
        for activity in Activity<RestActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
