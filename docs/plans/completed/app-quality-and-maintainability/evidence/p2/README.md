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
| Cached model construction | 152.41 | 157.12 | 151.28 |
| Calendar and all activity dates | 2899.43 | 23.76 | 0.32 |
| 20 calendar rows | 51.86 | 0.10 | 0.09 |
| All 40 latest summaries | 499.80 | 20.85 | 1.22 |
| One exercise history | 6.11 | 2.15 | 0.00 |
| Snapshot reservation | 143.56 | 216.07 | 76.72 |
| Snapshot ACK commit | 412.29 | 575.05 | 347.38 |

Durable enqueue/read/retire took 1.40 ms on the small fixture's first
use, then 0.94–1.11 ms; the large fixture took
1.08–1.94 ms. The first calendar/index build and first summaries
remain visible above; repeat-read speedups do not imply index construction is
free. Cold construction did not improve. Snapshot persistence remains the
dominant synchronous cost.

The large stored envelope is **279,858 bytes** (from 4,415,615 bytes of JSON);
the small envelope remains 49,207 bytes. Every row is retained. The final local
unit run passed **330 tests**, including durable writes, shared numerical/calendar
contracts and the oversized recovery cases below. [sources-after.json](sources-after.json)
contains its exact copied source hashes and corresponds to [after.json](after.json).

The earlier full UI run passed all **18 UI tests**. [Raw UI wall samples](ui-after.json)
record two successful fresh launches per dataset, preserving 288 and 24,960 sets.
Its large cached launches to the calendar were 3.61/3.63 seconds; the swipe was
588/479 ms, list opening plus multiple synthesized swipes 16.93/17.05 seconds,
and detail opening 2.35/1.78 seconds. These include XCTest overhead and animations.

A screenshot-driven follow-up limits categorical date-axis labels to three
representative dates, anchored inside the plot, while retaining every point.
Both history journeys passed again. [Small](history-small-detail.png) and
[five-year](history-large-detail.png) captures, [source hashes](sources-ui.json)
and [raw wall samples](ui-chart-labels.json) retain that normal-text result.
`HistoryView.swift` matches the final unit-run source exactly; the persistence
and recovery changes were subsequently covered by the full unit suite. The PR
runs all unit and UI tests together for its exact final reviewed head.

## Bounded changes and remaining costs

`TrainingHistoryIndex` builds date/session/exercise lookups once per published
session/set/catalog change. It preserves session precedence and delegates cohort
semantics to the existing shared metrics contract. Requested summaries are
invalidated together with the index. Exercise list rows are lazy and aggregate
only their latest session. Calendar projection's civil-date truth table is
unchanged. No account authority, attempt token or pending write lives in this
read model.

`StateSnapshotStore` is extracted from the runner recovery file. It retains one
live envelope, reusing it only when the defaults object, user ID and current
persisted bytes match. Another writer, legacy payload, corruption or deletion
therefore supersedes that value. All revisions, ACK transforms, tombstone rules
and synchronous ordering-write-before-outbox-removal remain at the same
main-actor boundary. No asynchronous save is added. Large envelopes use the
lossless wrapper below; oversized fallback semantics apply to every writer.

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
failed-save handling retains the durable intent or stores a small invalidation
marker before retiring an acknowledged correction. The marker requires a full
reload and prevents delayed ACKs from recreating stale cached rows.
This is lossless encoding, with no history trimming or retention-policy change.

The cached UI test verifies exact seeded set counts before termination and on
two fresh launches. Production preference writes do not call `synchronize()`;
the diagnostic call used while tracing the failure was removed. An older app
that cannot decode the wrapper must perform its existing full reload; separate
outboxes/checkpoints remain in their existing format. A downgrade while offline
can therefore lack cached browsing until that reload succeeds. No server or
schema migration is required.

## Oversized snapshot and mutation recovery

Independent review exposed that rejecting an oversized packed value could
block live presentation or discard a correction's recovery intent. The final
fallback lives in the shared store's write path, covering full responses,
request reservations, session creation and every mutation ACK. If packing is
too large, the store persists a small invalidation marker with the exact
revision, latest-full-request revision and mutation generation, then keeps the
latest validated rows in its single process-local envelope. That live value is
still fenced by defaults identity, account and exact persisted marker bytes.
All clients in the process transform those latest rows; they do not resurrect
an older model's fallback. Reads use full cursors while in this mode.

A cold process has no live envelope and sees only the invalidation marker, so
it must fetch fully before trusting rows. Explicit invalidation, deletion or
external replacement also clears the live value and blocks stale ACK fallback.
This trades offline browsing for correctness only when an envelope cannot be
stored; the five-year fixture fits the compressed path and survives relaunch.
No server data is trimmed. If even the ordering marker cannot advance, the
correction intent remains queued and the mounted model still distinguishes the
accepted edit from a failed recovery write.

Regression coverage exercises real incompressible packing failure, repeated
live refreshes, cold marker reads, catalog follow-up, stale request/ACK guards,
and a complete create/log/correct/finish/discard flow while oversized. Saturated
revision coverage separately verifies intent retention when neither snapshot
nor marker can advance. The final local unit run and
[copied-source manifest](sources-after.json) are recorded with the PR's
fresh exact-head review and complete CI suite.

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
