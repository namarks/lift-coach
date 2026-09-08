import AVFoundation
import XCTest
@testable import TresFort

final class TimerCueVoiceTests: XCTestCase {
    private func voice(
        _ id: String, _ quality: AVSpeechSynthesisVoiceQuality,
        language: String = "en-US",
        traits: AVSpeechSynthesisVoice.Traits = []
    ) -> TimerCueVoice.Option {
        .init(identifier: id, language: language, quality: quality, traits: traits)
    }

    private func choose(
        _ voices: [TimerCueVoice.Option], language: String = "en-US",
        defaultIdentifier: String? = "compact"
    ) -> String? {
        TimerCueVoice.preferredIdentifier(
            in: voices, language: language, defaultIdentifier: defaultIdentifier)
    }

    func testDownloadedVoicesReplaceCompactDefaultWithoutRestart() {
        let compact = voice("compact", .default)
        let enhanced = voice("enhanced", .enhanced)
        let premium = voice("premium", .premium)
        XCTAssertEqual(choose([compact]), "compact")
        XCTAssertEqual(choose([compact, enhanced]), "enhanced")
        XCTAssertEqual(choose([compact, enhanced, premium]), "premium")
        XCTAssertEqual(choose([compact]), "compact") // Download removed.
    }

    func testQualityWinsOverDialectButNotOverLanguage() {
        XCTAssertEqual(choose([
            voice("compact", .default),
            voice("british", .enhanced, language: "en-GB"),
            voice("french", .premium, language: "fr-FR")
        ]), "british")
    }

    func testEqualQualityPrefersUsersEnglishDialect() {
        XCTAssertEqual(choose([
            voice("american", .premium),
            voice("british", .premium, language: "en-GB")
        ], language: "en_GB"), "british")
    }

    func testEnglishAnnouncementsKeepAnEnglishVoiceOnOtherLocales() {
        XCTAssertEqual(choose([
            voice("british", .enhanced, language: "en-GB"),
            voice("american", .enhanced),
            voice("french", .premium, language: "fr-FR")
        ], language: "fr-FR"), "american")
    }

    func testNoveltyAndPersonalVoicesCannotReplaceNormalVoice() {
        XCTAssertEqual(choose([
            voice("compact", .default),
            voice("novelty", .premium, traits: .isNoveltyVoice),
            voice("personal", .premium, traits: .isPersonalVoice)
        ]), "compact")
    }

    func testCompactFallbackKeepsSystemDefaultRatherThanAnotherLegacyVoice() {
        XCTAssertEqual(choose([
            voice("a-legacy-voice", .default), voice("compact", .default)
        ]), "compact")
    }

    func testTieIsStableAcrossEnumerationOrder() {
        let voices = [voice("b", .enhanced), voice("a", .enhanced)]
        XCTAssertEqual(choose(voices), "a")
        XCTAssertEqual(choose(Array(voices.reversed())), "a")
    }

    func testNoSuitableEnglishVoiceLeavesSelectionToSystemFallback() {
        XCTAssertNil(choose([]))
        XCTAssertNil(choose([voice("french", .premium, language: "fr-FR")]))
    }

    func testSelectionResolvesAnInstalledEnglishVoice() throws {
        let selected = try XCTUnwrap(TimerCueVoice.preferred())
        XCTAssertTrue(selected.language.lowercased().hasPrefix("en-"))
        XCTAssertFalse(selected.voiceTraits.contains(.isNoveltyVoice))
        XCTAssertFalse(selected.voiceTraits.contains(.isPersonalVoice))
    }
}
