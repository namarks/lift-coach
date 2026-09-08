import AppIntents
import Foundation

/// LiveActivityIntent runs in the app process. The mounted runner owns this
/// handler; an obsolete activity cannot control a new timer or another user.
@MainActor
enum WorkoutTimerControl {
    static var handler: ((String, String) async -> Bool)?
}

struct WorkoutTimerControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Control workout timer"
    static var isDiscoverable = false
    @Parameter(title: "Timer") var timerID: String
    @Parameter(title: "Action") var action: String

    init() {}
    init(timerID: String, action: String) { self.timerID = timerID; self.action = action }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await WorkoutTimerControl.handler?(timerID, action) == true else {
            throw TimerUnavailable()
        }
        return .result()
    }

    private struct TimerUnavailable: LocalizedError {
        var errorDescription: String? { "Open Tres Fort to resume this workout." }
    }
}
