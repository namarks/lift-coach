# Measured client hot paths

## Reproduction and scope

Run the unsigned current-iPhone command in `docs/IOS-VERIFICATION.md`; use
`--only-testing TresFortTests/HistoryPerformanceTests` for the main-actor probes,
or `--only-testing TresFortUITests/HistoryJourneyTests` for cached UI journeys.
Both are also included in the full suite. Raw `HISTORY_PERF` and `HISTORY_UI_PERF`
JSON lines are retained in the result bundle's `xcodebuild.log`.

Measurements use an Apple M4 Pro host with 24 GiB RAM, Xcode 26.3 (17C529),
XcodeGen 2.45.3, and an iPhone 17 simulator on iOS 26.2 (23C52), at normal text
size. These are Debug simulator observations, not physical-iPhone frame rates
or release-build guarantees. The before probe was added to P1 source `2a6fbd9`;
`BaselineProbe.swift.txt` and `sources-before.json` retain the exact probe and
copied sources. The source manifest includes that uncommitted probe.

| Dataset | Sessions | Sets | Exercises | Snapshot envelope |
|---|---:|---:|---:|---:|
| Small, about three weeks | 12 | 288 | 40 | 49,207 bytes |
| Five years, four workouts/week | 1,040 | 24,960 | 40 | 4,415,615 bytes |

Each session has six movements with four rep sets each. Dates are deterministic
civil dates ending September 8, 2026. There are no external/manual activities
in this lifting-history fixture. Both sides use the same retained rows; snapshot
JSON row content is unchanged. Stored byte sizes after compression are recorded
in the final results below. The UI fixture adds an empty plan and synthetic catalog so
opening History cannot trigger a live fetch. An isolated fixture namespace and
in-memory token store prevent access to real accounts or Keychain.

## What the probes measure

Main-actor probes run five samples, recording each sample rather than imposing
unstable timing assertions on shared CI machines. Cached model construction uses
a new defaults object each time, forcing envelope decoding and application to
published state. It excludes process launch, fixture creation and disk seeding.
Calendar work projects 30 days and prepares all real activity dates; scroll work
prepares up to 20 session rows. The list workload requests the latest summary
for all 40 exercises (before: full history then `.last`; after: latest-only).
Detail requests the complete history of exercise 0. Probes execute in the order
shown below, so list/detail queries reuse the index built by calendar work. Initial index/summary work
is recorded separately from repeat reads, so cache reuse cannot hide it.

Reservation and ACK probes use the real snapshot store's synchronous revision
and persistence paths. The ACK replaces one set in the newest snapshot; it is
a component measurement, not an HTTP round-trip or complete runner log flow.
The added outbox probe enqueues, reads and retires a synthetic attempt-bound
intent through the real store. Existing behavioral tests and the training UI
smoke cover actual log/ACK ordering separately.

The UI test seeds once, terminates the app, and performs two fresh cached
launches per dataset. Each launch opens the calendar, swipes the feed, switches
to Exercises, scrolls to exercise 0 and opens its detail. Wall timings include
XCTest event synthesis, waits and animations; the list timing also includes
scrolling through the list. They establish repeatable interaction evidence,
not main-thread CPU measurements or animation hitch rates. In particular, a
first-swipe idle wait must not be interpreted as a measured rendering stall.

## Main-actor observations

Milliseconds, five-year history. Before is the median of five uncached calls;
after shows the first call and median of the remaining four calls. Raw samples
for both dataset sizes are in [before.json](before.json) and [after.json](after.json).
The cached-construction samples force decoding each time; the first reservation
after those probes also repopulates the store cache.

| Component | Before median | After first | After repeats median |
|---|---:|---:|---:|
| Cached model construction | 152.41 | 158.04 | 160.75 |
| Calendar and all activity dates | 2899.43 | 29.68 | 0.36 |
| 20 calendar rows | 51.86 | 0.11 | 0.10 |
| All 40 latest summaries | 499.80 | 24.92 | 1.19 |
| One exercise history | 6.11 | 1.96 | 0.00 |
| Snapshot reservation | 143.56 | 163.87 | 80.32 |
| Snapshot ACK commit | 412.29 | 370.93 | 366.70 |

Durable enqueue/read/retire took 12.92 ms on the small fixture's first use,
then 1.13–2.04 ms; all five large-fixture samples took 1.09–1.54 ms. That first
cold store access remains visible rather than being hidden in a warm median.
The first calendar/index build and first summaries remain visible above;
repeat-read speedups do not imply that index construction is free. Cold
construction did not improve. Snapshot persistence remains the dominant
synchronous cost.

The large stored envelope is now **264,174 bytes** (from 4,415,615 bytes of JSON);
the small envelope remains 49,207 bytes. Both preserve every row. The full final
run passed **326 unit tests and 18 UI tests**, including account/attempt ordering,
tombstones, stale ACKs, shared numerical/calendar contracts, cache replacement,
legacy reads, corruption and an incompressible oversized-envelope rejection.

[Raw UI wall samples](ui-after.json) record two successful fresh launches per
dataset, preserving 288 and 24,960 sets respectively. Large cached launches to
the calendar were 3.61/3.63 seconds; the swipe was 588/479 ms, list opening plus
multiple synthesized swipes 16.93/17.05 seconds, and detail opening 2.35/1.78
seconds. These include XCTest overhead and animations as described above.
[Small](history-small-detail.png) and [five-year](history-large-detail.png) detail
captures retain the normal-text result. [sources-after.json](sources-after.json)
contains the copied source hashes used by the full local run. A screenshot-driven
follow-up limits categorical date-axis labels to three representative dates
while retaining every plotted point. Both history journeys passed again; the
linked detail captures come from that follow-up, whose [source manifest](sources-ui.json)
and [raw wall samples](ui-chart-labels.json) are retained separately. Only
`HistoryView.swift` differs between these two iOS source manifests. The final
commit also removes a trailing blank line from `StateSnapshotStore.swift`.

## Bounded changes and remaining costs

`TrainingHistoryIndex` builds date/session/exercise lookups once per published
session/set/catalog change. It preserves session precedence and delegates cohort
semantics to the existing shared metrics contract. Requested summaries are
invalidated together with the index. Exercise list rows are lazy and aggregate
only their latest session. Calendar projection's civil-date truth table is
unchanged. No account authority, attempt token or pending write lives in this
read model.

`StateSnapshotStore` is extracted from the runner recovery file. It retains one
decoded envelope, reusing it only when the defaults object, user ID and current
persisted bytes match. Another writer, legacy payload, corruption or deletion
therefore supersedes the cache. All revisions, ACK transforms, tombstone rules
and synchronous commit-before-outbox-removal behavior remain at the same
main-actor boundary. No asynchronous save is added. Large envelopes use the lossless wrapper described
below; the full JSON schema and account key stay the same.

The index stores live set values grouped by session and working set values by
exercise, plus session/catalog maps and requested summaries. It trades temporary
memory proportional to current history for repeated scans; it retains no prior
index after invalidation. The snapshot cache holds one envelope and its stored bytes (compressed for
the large fixture), sharing Swift value storage where possible. It does not retain a cache per user or introduce new disk retention.
This is a structural memory accounting, not a measured peak-RSS claim.

Cold decoding and whole-envelope encoding remain linear in retained history.
Their remaining costs warrant follow-up if history materially exceeds this fixture or
release profiling shows interaction stalls. Moving writes off actor or splitting
the persistent envelope would change cross-model ordering and crash recovery;
this slice keeps those invariants instead of inferring a storage redesign from
static file size. No backend extraction is needed for the measured iOS paths.

## Confirmed large-snapshot persistence defect

Fresh-process UI checks found that the large history disappeared after relaunch,
including after a diagnostic wait for pending preference writes. The owned
simulator's [platform log](preferences-limit.txt) confirms iOS rejected the
4,415,694-byte UI envelope at its 4 MiB data-value boundary and switched the
preferences object into direct mode. In-process reads still saw that value,
while the next process saw only the prior 87-byte reservation. The small marker
and catalog writes after that invalid value were also absent after relaunch.
Thus the original large constructor/write timings describe in-process work;
they were not evidence that the large cache survived a process boundary.

Envelopes of at least 256 KiB now use a `TFSS1` prefix plus Foundation LZFSE
compression. Small envelopes remain plain JSON. Reads accept both forms and
legacy raw StateResponse payloads. Compression/decompression errors fail closed;
a packed value at or above 4 MiB is rejected before calling UserDefaults, so
existing failed-save behavior retains pending writes instead of claiming success.
This is lossless encoding, with no history trimming or retention-policy change.

The cached UI test verifies exact seeded set counts before termination and on
two fresh launches. Production preference writes do not call `synchronize()`;
the diagnostic call used while tracing the failure was removed. An older app
that cannot decode the wrapper must perform its existing full reload; separate
outboxes/checkpoints remain in their existing format. A downgrade while offline
can therefore lack cached browsing until that reload succeeds. No server or
schema migration is required.

## Investigation budgets

For this hardware/runtime and five-year dataset, investigate a repeatable
regression beyond: 50 ms for first calendar/index or all latest summaries; 5 ms
for repeated calendar/scroll preparation; 10 ms for first exercise aggregation;
300 ms for cached model construction; 200 ms for a snapshot reservation; 500 ms
for synchronous ACK persistence; 10 ms for enqueue/read/retire of one outbox
intent. These budgets are selected from observed costs and leave headroom for
Debug host variance. They are component investigation thresholds, not promises
of 60/120 fps or automatic wall-time CI gates. Small-history results and raw
first/warm samples remain visible alongside the five-year comparison.
