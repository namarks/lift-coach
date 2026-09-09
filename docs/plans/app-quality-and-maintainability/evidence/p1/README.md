# P1 basic usability evidence — September 8, 2026

This record accompanies the basic usability implementation. Live completion and
authority boundaries belong only in [the canonical plan](../../plan.md).

## What changed and why

Empty/loading guidance uses a readable system callout in the primary text
color after XCTest identified low contrast in the original guidance. Secondary
text uses `#A1A1AA` on the existing dark palette. Enabled text previously using the
much darker decorative token now uses the secondary text color. Runner metadata
and load controls stack at accessibility sizes; exercise names wrap. Sign-in,
onboarding and rest can scroll, and direct load entry uses a scrolling large
sheet with a reachable Save action. Custom fonts retain Dynamic Type scaling.

Exercise/demo/edit/delete/recovery and load-step controls provide context,
values and at least 44-point targets. Exercise completion/skipping has a text
cue in addition to color. Rest-complete pulsing and onboarding step animation
honor the system Reduce Motion preference. The rest screen keeps an explicit
preview action when large text uses scrolling instead of swipe-to-minimize.

## Verification scope

The required suite uses the current iPhone 17, normal text sizes, Xcode 26.3
(17C529), XcodeGen 2.45.3 and iOS 26.2 (23C52), through the
[verification command](../../../../IOS-VERIFICATION.md). It covers the P0
fixtures plus onboarding, decimal keyboard entry, rest completion and correction
recovery. Native audits check hit regions, descriptions and clipped text in four
visible entry/runner viewports. Contrast has the separate policy checks below.

Earlier SE/extreme-text investigation informed the retained usability fixes.
Per the September 8 owner steering, it is not part of the delivery matrix and
no further exhaustive older-device/extreme-font testing is required. Captures
and results retained here prioritize the normal-size current-device journey.

The complete run passed **322 unit tests and 16 UI tests**. The retained
[sources.json](sources.json) identifies the exact copied iOS sources. Screenshots
are synthetic observations, not pixel baselines.

| Normal-size current-iPhone capture | Observation |
|---|---|
| [Runner](ordinary-workout.png) | Contextual load and rep controls |
| [Load keyboard](journey-weight-keyboard.png) | Decimal load entry and Save |
| [Correction keyboard](journey-correction-keyboard.png) | Editing a logged set |
| [Correction recovery](journey-correction-recovery.png) | Rejected correction retains original values |
| [Group onboarding](journey-onboarding-group.png) | Optional step stays reachable |
| [Rest complete](journey-rest-complete.png) | Explicit end-rest action |
| [Finish](journey-finish.png) | Summary and explicit completion |

## Contrast verification

The iOS 26.2 native audit reports contrast failures on light text over the dark
gradient, including the empty guidance, load error, retry action, runner set
metadata and summary values. [Apple documents investigating contrast false
positives](https://developer.apple.com/videos/play/wwdc2023/10035/).
The raw cropped audit attachments are retained as `contrast-*.png`; their
unmodified glyph cores are `#F4F4F5` (the two paragraphs) and `#A1A1AA` (the
summary value). Run `python3 measure-contrast.py` here to reproduce the pixel
observations in `contrast-measurements.json`. The dark-reference sample includes
anti-aliased edges, so its core-pixel ratio is a conservative diagnostic rather
than a claim that every partially covered edge pixel meets a WCAG threshold.

`ThemeAccessibilityTests` enforces the 4.5:1 AA threshold for all enabled palette
text colors against every dark surface, including the gradient endpoints.
It also checks black primary-action text on amber. These tests check resolved
opaque colors, not the composition of every possible view or an opacity change.
The native contrast heuristic is excluded from CI assertions, with no per-label
exception list. Its observed warnings remain diagnostic evidence and require
visual review; target-size, description and clipping audits still fail normally.
Future toolchain
updates should re-evaluate whether the native contrast check is reliable here.

## Limits and optional observations

Automated tests do not establish physical VoiceOver speech/focus, actual OS
Reduce Motion, audio/lock-screen cues or interruption behavior. Those observations
are useful follow-up evidence and are explicitly not a delivery gate. No
installation, signing, distribution, deployment, migration or production-data
change is implied by this repository delivery. The canonical plan continues
with measured performance and bounded maintainability work.
