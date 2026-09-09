import Foundation
import Combine

/// Only explicitly saved words enter checkpoints or terminal writes. Audio and
/// unapproved recognition results never enter this value.
struct WorkoutFeedbackBaseline: Codable, Equatable {
    let notes: String?
    let perceivedFatigue: Int?
    var wire: [String: Any] {
        ["notes": notes as Any? ?? NSNull(), "perceived_fatigue": perceivedFatigue as Any? ?? NSNull()]
    }
}

struct WorkoutFeedback: Codable, Equatable {
    var notes: String?
    var perceivedFatigue: Int?
    var expected: WorkoutFeedbackBaseline? = nil

    var isEmpty: Bool { notes == nil && perceivedFatigue == nil }

    /// An explicitly saved empty field clears that field. A missing feedback
    /// envelope (Skip) omits both fields at the API boundary.
    var finishBody: [String: Any] {
        var body = WorkoutFeedbackBaseline(notes: notes, perceivedFatigue: perceivedFatigue).wire
        body["status"] = "completed"
        if let expected { body["expected_feedback"] = expected.wire }
        return body
    }
}

enum WorkoutFeedbackTranscription {
    case transcript(String)
    case finished
    case failure(Error)
}

@MainActor
protocol WorkoutFeedbackTranscribing: AnyObject {
    /// Permission is requested only by start, following an explicit Talk tap.
    func start(result: @escaping @MainActor (WorkoutFeedbackTranscription) -> Void) async throws
    func finish()
    func stop()
}

enum FeedbackRecordingError: LocalizedError {
    case denied, unavailable, interrupted
    var errorDescription: String? {
        switch self {
        case .denied: return "Recording permission is off. You can type instead or skip."
        case .unavailable: return "On-device transcription is unavailable. You can type instead or skip."
        case .interrupted: return "Recording stopped. Review the text, type instead, or skip."
        }
    }
}

/// One editor presentation. Its unapproved text lives only in memory. The
/// generation fences both recognition callbacks and asynchronous permission.
@MainActor
final class WorkoutFeedbackEditor: ObservableObject {
    @Published private(set) var text: String
    @Published var fatigue: Int?
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var message: String?
    private let transcriber: any WorkoutFeedbackTranscribing
    private var generation: UUID?
    private var beforeRecording = ""
    let initial: WorkoutFeedback?

    init(initial: WorkoutFeedback?, transcriber: any WorkoutFeedbackTranscribing) {
        self.initial = initial
        self.transcriber = transcriber
        text = initial?.notes ?? ""
        fatigue = initial?.perceivedFatigue
    }

    func talk() async {
        guard generation == nil else { return }
        let token = UUID()
        generation = token
        beforeRecording = text
        message = nil
        isStarting = true
        do {
            try await transcriber.start { [weak self] result in
                guard let self, self.generation == token else { return }
                switch result {
                case .transcript(let transcript):
                    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    self.text = self.beforeRecording.isEmpty ? transcript : self.beforeRecording + "\n" + transcript
                case .finished:
                    self.stop()
                case .failure:
                    self.stop()
                    self.message = FeedbackRecordingError.interrupted.localizedDescription
                }
            }
            guard generation == token else { return }
            isStarting = false
            isRecording = true
        } catch {
            guard generation == token else { return }
            stop()
            message = (error as? FeedbackRecordingError)?.localizedDescription
                ?? FeedbackRecordingError.unavailable.localizedDescription
        }
    }

    func edit(_ value: String) {
        stop()
        text = value
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        isFinalizing = true
        transcriber.finish()
    }

    func stop() {
        isFinalizing = false
        generation = nil
        isStarting = false
        isRecording = false
        transcriber.stop()
    }

    func cancelRecording() {
        let wasActive = generation != nil
        stop()
        if wasActive { text = beforeRecording }
    }

    func interrupt() {
        guard generation != nil else { return }
        stop()
        message = FeedbackRecordingError.interrupted.localizedDescription
    }

    func approvedFeedback() -> WorkoutFeedback {
        stop()
        // An empty recognition never erases existing feedback. A deliberate
        // typed deletion of an existing note is represented by an empty string.
        return WorkoutFeedback(notes: text.isEmpty && initial?.notes == nil ? nil : text,
                               perceivedFatigue: fatigue, expected: initial?.expected)
    }
}
