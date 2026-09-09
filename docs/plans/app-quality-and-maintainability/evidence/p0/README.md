# P0 synthetic simulator baseline

Captured September 8, 2026 with Xcode 26.3 (17C529), XcodeGen 2.45.3,
iOS 26.2 (23C52), iPhone 17 simulator. The complete unsigned run passed
320 XCTest unit tests and 8 UI smoke tests. `sources.json` records SHA-256
hashes of the exact copied iOS source inputs. CI supplies current-head evidence
separately; these screenshots record the baseline rather than live gate status.

All values are synthetic. Sign-in records an intent without invoking Apple's
provider UI; network responses come from the in-process fixture protocol.
Screenshots were exported directly from XCTest attachments without retouching.
Status-bar time is simulator wall time; training dates and workout elapsed time
use the fixture clock. These are visual/walkthrough evidence, not pixel assertions.

- [Sign-in entry](fresh-sign-in.png)
- [Verified empty plan](verified-empty-plan.png) and [created first workout](created-first-workout.png)
- [Failed initial load](failed-initial-load.png)
- [Ordinary workout](ordinary-workout.png), [bodyweight](bodyweight-workout.png), and [timed](timed-workout.png)
- [Pending write](pending-write.png)
- [Rejected correction with original retained](correction-failure-original-retained.png)
- [Ready to finish](ready-to-finish.png) and [acknowledged completion](acknowledged-completion.png)

No VoiceOver usability, large-accessibility-text, physical-device audio,
lock-screen, or interruption acceptance is claimed by this baseline.
