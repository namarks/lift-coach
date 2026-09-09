# Physical iPhone feedback verification

Use the separate `FeedbackVerification` development target to exercise the
production `WorkoutFeedbackEditor` and `OnDeviceFeedbackTranscriber` without
loading Tres Fort's account, API, local history or release scheme. It keeps
approved test text only in screen memory. Use synthetic phrases.

Generate and build with existing local signing assets:

```sh
cd ios
xcodegen generate --spec feedback-verification.yml
xcodebuild -project FeedbackVerification.xcodeproj -scheme FeedbackVerification \
  -configuration Debug -destination generic/platform=iOS \
  -derivedDataPath ../.artifacts/feedback-device build
```

Install on the already registered, unlocked development iPhone with Xcode or
`devicectl`. Do not add `-allowProvisioningUpdates`, alter credentials, upload
to TestFlight, or replace the Tres Fort app. If a private development installer
is needed for a remote device, obtain authorization for the actual download
audience, serve only that installer and its manifest, and remove the temporary
endpoint after the check. Build artifacts and provisioning material stay out
of Git.

Perform and record the observed result in the canonical plan:

1. On a fresh permission state, type a short note before choosing Talk. Deny
   speech or microphone access when prompted. Confirm the typed text remains,
   Type instead works, and Skip can finish the check.
2. With permission granted, choose Talk, speak a short synthetic phrase, and
   Stop. Confirm the final words arrive, capture stops, the text can be edited,
   and only Save feedback displays the approved text.
3. Start another recording and Cancel. Confirm the earlier typed text returns.
   Start again and background the app. Confirm capture stops and late results
   cannot replace a typed correction after returning.
4. Relaunch the checker. Its prior test text must be gone. Remove the checker
   when testing is finished. This target does not verify persisted finish
   delivery; the app's simulator journeys and shared D1/MCP fixture cover that
   separate boundary.

An unavailable language/model is a valid fallback observation, but does not
prove successful on-device transcription. Simulator permission substitutes
do not count as fresh physical-device grant/denial evidence.
