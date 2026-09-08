import AVFoundation

/// All timer phrases are currently English. Prefer natural installed voices
/// without requesting personal-voice access or downloading assets in a workout.
enum TimerCueVoice {
    struct Option {
        let identifier: String
        let language: String
        let quality: AVSpeechSynthesisVoiceQuality
        var traits: AVSpeechSynthesisVoice.Traits = []
    }

    static func preferred() -> AVSpeechSynthesisVoice? {
        // Re-enumerate for each cue so a newly downloaded voice is picked up
        // without restarting the app. The same policy runs on devices/Release.
        let language = englishLocale(AVSpeechSynthesisVoice.currentLanguageCode())
        let fallback = AVSpeechSynthesisVoice(language: language)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let identifier = preferredIdentifier(
            in: voices.map {
                Option(identifier: $0.identifier, language: $0.language,
                       quality: $0.quality, traits: $0.voiceTraits)
            },
            language: language,
            defaultIdentifier: fallback?.identifier)
        return voices.first { $0.identifier == identifier } ?? fallback
    }

    static func preferredIdentifier(
        in voices: [Option],
        language: String,
        defaultIdentifier: String?
    ) -> String? {
        let locale = normalized(englishLocale(language))
        return voices.filter {
            normalized($0.language).split(separator: "-").first == "en"
                && !$0.traits.contains(.isNoveltyVoice)
                && !$0.traits.contains(.isPersonalVoice)
        }.sorted { lhs, rhs in
            // Quality wins over dialect: a downloaded English voice improves
            // the cue even when the device's own dialect is still compact.
            if lhs.quality != rhs.quality {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            let lhsLocale = normalized(lhs.language) == locale
            let rhsLocale = normalized(rhs.language) == locale
            if lhsLocale != rhsLocale { return lhsLocale }
            let lhsDefault = lhs.identifier == defaultIdentifier
            let rhsDefault = rhs.identifier == defaultIdentifier
            if lhsDefault != rhsDefault { return lhsDefault }
            return lhs.identifier < rhs.identifier
        }.first?.identifier
    }

    private static func englishLocale(_ language: String) -> String {
        normalized(language).split(separator: "-").first == "en"
            ? language.replacingOccurrences(of: "_", with: "-") : "en-US"
    }

    private static func normalized(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
