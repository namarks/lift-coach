import AVFoundation
import Speech

@MainActor
final class OnDeviceFeedbackTranscriber: WorkoutFeedbackTranscribing {
    private var generation: UUID?
    private var callback: (@MainActor (WorkoutFeedbackTranscription) -> Void)?
    private var finalizationTimeout: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var observers: [NSObjectProtocol] = []
    private var previousAudio: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    func start(result: @escaping @MainActor (WorkoutFeedbackTranscription) -> Void) async throws {
        stop()
        let token = UUID()
        generation = token
        callback = result
        guard let recognizer = SFSpeechRecognizer(locale: .current),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            stop()
            throw FeedbackRecordingError.unavailable
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == token else { throw CancellationError() }
        guard speech == .authorized else { stop(); throw FeedbackRecordingError.denied }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard generation == token else { throw CancellationError() }
        guard microphone else { stop(); throw FeedbackRecordingError.denied }
        guard recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            stop(); throw FeedbackRecordingError.unavailable
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            previousAudio = (audio.category, audio.mode, audio.categoryOptions)
            try audio.setCategory(.record, mode: .measurement)
            try audio.setActive(true)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw FeedbackRecordingError.unavailable
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            self.engine = engine
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
                let transcript = recognition?.bestTranscription.formattedString
                let ended = error != nil || recognition?.isFinal == true
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let transcript { result(.transcript(transcript)) }
                    if ended {
                        self.stop()
                        result(error == nil ? .finished : .failure(FeedbackRecordingError.interrupted))
                    }
                }
            }
            for notification in [AVAudioSession.interruptionNotification,
                                 AVAudioSession.routeChangeNotification,
                                 AVAudioSession.mediaServicesWereResetNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: notification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.stop()
                        result(.failure(FeedbackRecordingError.interrupted))
                    }
                })
            }
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw FeedbackRecordingError.unavailable
        }
    }

    /// Stop collecting audio, but allow the recognizer to deliver the final
    /// words. Editing/cancel/leaving still calls stop(), which fences all work.
    func finish() {
        guard let token = generation else { return }
        releaseMicrophone()
        request?.endAudio()
        finalizationTimeout?.cancel()
        finalizationTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            let callback = self.callback
            self.stop()
            callback?(.finished)
        }
    }

    private func releaseMicrophone() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    func stop() {
        generation = nil
        callback = nil
        finalizationTimeout?.cancel()
        finalizationTimeout = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        releaseMicrophone()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if let previousAudio {
            let audio = AVAudioSession.sharedInstance()
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            try? audio.setCategory(previousAudio.0, mode: previousAudio.1, options: previousAudio.2)
            self.previousAudio = nil
        }
    }
}
