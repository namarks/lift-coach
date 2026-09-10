# App Store screenshot capture

This workflow prepares draft assets through the real app screens with fictional
training data. It does not publish images or use an App Store account. Submission
readiness and publication authority remain in [plan.md](plan.md).

From the checkout whose UI should be captured, with Xcode 26.3, XcodeGen and the
iOS 26.2 simulator runtime installed:

```sh
bash scripts/capture-app-store-screenshots.sh .artifacts/app-store-screenshots
```

Choose a new output directory; the command refuses to overwrite an existing set.
It creates its own iPhone 17 Pro Max simulator and unsigned build, runs two UI
journeys, exports the five named screenshots, and removes its temporary build
and simulator. It retains failed-test evidence if verification fails.

The output contains Today, the workout runner, reusable workouts, History and
editable feedback. All five images must be opaque RGB PNGs at 1320 × 2868 pixels,
an accepted portrait size for Apple's 6.9-inch iPhone screenshot class. The
manifest records image hashes, source commit/tree, checkout changes, locale,
device/runtime and capture time; `sources.json` hashes every tested iOS input,
and `capture-tests.log` retains the successful UI-test evidence. Source changes
during capture cause the command to fail rather than misidentify the images.

The `app-store` launch fixture is compiled only for Debug simulator builds.
Its ephemeral URL session intercepts requests, its token store does not read
Keychain, and its defaults use a dedicated synthetic namespace. The sample
workouts and history represent no person. This asset fixture omits the QA banner;
the other test fixtures retain their labels. No production account, integration,
invite code or personal training record is required.

Before publication, capture from the selected final candidate source and inspect
every image for system alerts, clipped controls, accidental personal data and
claims inconsistent with the release. Simulator capture demonstrates the visible
UI; it does not establish physical-device behavior, actual speech recognition or
App Review approval. Keep the images as drafts until that candidate comparison
and the separately authorized metadata publication are complete.

Specification checked 2026-09-10:
[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
