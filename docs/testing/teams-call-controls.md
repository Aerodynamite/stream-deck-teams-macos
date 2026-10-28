# Microsoft Teams controls live qualification

Date created: 2026-09-02

Use this checklist with the packaged Stream Deck plugin and the currently installed Microsoft Teams desktop client. Automated results belong in the repository verification output. This document is for behavior that can only be proven in a live meeting.

## Test setup

Record these values before testing:

| Field | Result |
|---|---|
| macOS version | Not run |
| Stream Deck version | Not run |
| Teams version | Not run |
| Stream Deck device | Not run |
| Meeting tenant or account type | Not run |
| Organizer or attendee | Not run |
| Teams interface language | Not run |
| Accessibility entry granted | Not run |

Use a disposable meeting. Keep a second participant or device connected for reaction delivery checks and for confirming that Leave never ends the meeting for everyone.

## Core controls

| Case | Expected result | Result |
|---|---|---|
| Mute from an unmuted state | Teams becomes muted and the Stream Deck key shows muted | Not run |
| Unmute from a muted state | Teams becomes unmuted and the key shows unmuted | Not run |
| Change microphone state in Teams, then press Stream Deck | The helper requests one explicit state and the key reconciles after the result | Not run |
| Change microphone state from a headset, then refresh the profile | The key refreshes to the exposed Teams state | Not run |
| Turn camera off from on | Teams camera stops and the key shows off | Not run |
| Turn camera on from off | Teams camera starts and the key shows on | Not run |
| Raise hand | The hand is raised and the key shows raised | Not run |
| Lower hand | The hand is lowered and the key shows lowered | Not run |
| Leave as attendee | The local participant leaves and the meeting continues | Not run |
| Leave as organizer | The local organizer leaves without selecting End meeting for all | Not run |

## Toolbar and window variants

Repeat mute, camera, hand, and leave in each applicable state:

| Variant | Result |
|---|---|
| Normal meeting toolbar visible | Not run |
| Meeting toolbar auto-hidden | Not run |
| Teams minimized | Not run |
| Compact sharing toolbar | Not run |
| Second display | Not run |
| Teams chat focused | Not run |
| PowerPoint Live or Whiteboard active | Not run |
| Multiple Teams windows | Not run |
| Guest meeting in another organization | Not run |

## Shortcut qualification

Shortcut fallback is disabled by default. Run these cases from a development shell with only the family under test enabled in `TEAMS_CONTROLS_SHORTCUT_FALLBACK`.

| Family | Other app focused | Teams chat focused | Teams minimized | Custom shortcut configured | Verdict |
|---|---|---|---|---|---|
| microphone | Not run | Not run | Not run | Not run | Disabled |
| camera | Not run | Not run | Not run | Not run | Disabled |
| hand | Not run | Not run | Not run | Not run | Disabled |
| leave | Not run | Not run | Not run | Not run | Disabled |

Do not enable a fallback in the packaged plugin until every focus case passes and the post-action Accessibility scan confirms the requested state.

## Reaction tap and hold

The default hold rate is 7 attempts per second. Confirm the picker remains open during repeats, presses are spaced about 143 ms apart, and slow picker setup does not produce a catch-up burst.

For each rate, hold Love for five seconds. Count the values separately. The helper's Accessibility count is not a delivery count.

| Attempts per second | Scheduled attempts | Accessibility accepted | Seen by second participant | Teams responsive | Result |
|---:|---:|---:|---:|---|---|
| 1 | Not run | Not run | Not run | Not run | Not run |
| 2 | Not run | Not run | Not run | Not run | Not run |
| 3 | Not run | Not run | Not run | Not run | Not run |
| 5 | Not run | Not run | Not run | Not run | Not run |
| 7 (default) | Not run | Not run | Not run | Not run | Not run |
| 10 | Not run | Not run | Not run | Not run | Not run |

Also verify:

- A tap sends exactly one reaction.
- Repeating starts only after the hold threshold.
- Release stops within one in-flight attempt.
- Holding beyond five seconds stops at the duration guard.
- Changing profiles while holding stops the session.
- Disconnecting the Stream Deck while holding stops the session.
- Another reaction or call-control key cannot overlap the active session.
- A Multi Action sends only one reaction.
- Reactions disabled by the organizer produce one clear alert.
- Ending the meeting stops without an orphaned helper or popover.

## Compatibility and privacy

| Case | Expected result | Result |
|---|---|---|
| English Teams UI | All direct controls qualify | Not run |
| Dutch Teams UI | All documented localized labels qualify | Not run |
| Packaged helper after plugin upgrade | Accessibility permission remains usable or prompts clearly | Not run |
| Helper and plugin logs | No meeting titles, participant names, or full Accessibility tree text | Not run |
| Current Teams update | All qualified controls still pass | Not run |
| Next Teams update | Re-run this checklist before claiming compatibility | Not run |

## Release decision

Do not call the plugin production-ready until all core controls pass in both directions, Leave is proven safe for attendee and organizer roles, and the default 7-per-second reaction wave is confirmed by a second participant.

## 2026-10-28 toolbar compatibility check

Client: Teams `26276.505.5234.9924`, English UI. These checks used the standalone helper built from the updated source, not the installed Stream Deck package.

- Confirmed live microphone and camera state discovery while unmuted and camera on.
- Confirmed a manually raised hand is reported as raised using the custom Accessibility description, despite the visible `Raise` label remaining unchanged.
- Confirmed `hand-lower`, `hand-raise`, and a final `hand-lower`, including post-action state verification. Hand restored to lowered.
- Confirmed one Love reaction accepted by Accessibility after removing the pre-opening scroll action. The Node burst runner also completed a tap with one accepted attempt and `key-up`, and a hold with 11 accepted attempts and `duration-limit` at 3308 ms. Delivery to another participant remains unverified.
- Leave was not pressed. Organizer and attendee safety, mute and camera changes in both directions, compact/minimized/hidden toolbars, other languages, packaged installation, and reaction hold delivery remain unverified.

## 2026-10-28 seven-per-second hold check

The default repeat rate is now 7 per second. A live native Love hold opened React once, reused the cached reaction button for all 9 accepted presses, and stopped at the duration guard at 3001 ms. Temporary aggregate timing instrumentation measured 143.31 to 145.50 ms between reaction press starts. Instrumentation was removed after verification. Picker setup counts toward the existing three-second session budget.

The Node runner also confirmed a tap produced exactly one accepted reaction with `key-up`, and releasing a hold produced 6 accepted reactions with `key-up` at 2485 ms.

These are Accessibility acceptance and timing results. Second-participant delivery, focus/window variants, other reactions, and profile/device-disconnect behavior at the new rate remain unverified.

## 2026-10-28 five-second hold check

The session limit is now five seconds, including picker setup, at the unchanged default of 7 presses per second. The native attempt cap is 50 to support the maximum permitted rate of 10 per second; the Node watchdog allows 6500 ms for the session and cleanup.

A live native Love hold accepted 21 of 21 presses and stopped with `duration-limit` at 5000 ms. A subsequent run through the Node runner accepted 23 of 23 and stopped at 5002 ms without triggering its watchdog. The first live attempt failed with a Teams reaction-control error; the two later attempts passed without code changes. Delivery to another participant and window/focus variants remain unverified.

## 2026-10-28 control latency check

Client: Teams `26276.505.5234.9924`, English UI, active meeting. Microphone and camera changes were explicitly approved for this check and restored to their starting states: microphone muted, camera on. Leave was not pressed.

The initial read-only status benchmark took 1954, 3458, and 2000 ms. Aggregate instrumentation found about 9200 individual attribute reads per scan, roughly 300 ms in picker recognition, and roughly 820 ms in state scoring. The changes share immutable label definitions, avoid repeated label-prefix allocation, skip scoring non-actionable nodes, and batch Accessibility attributes. Optimized status scans measured 350 to 762 ms across the later checks. Temporary instrumentation was removed.

Mute and camera verification now refreshes the discovered state controls immediately, with 20 ms polling while waiting for confirmation. If the target disappears, verification falls back to full discovery without pressing again. The operation lock remains held until confirmation or failure.

| Command | Previous helper | Optimized helper |
|---|---:|---:|
| Unmute | 3913 ms | 652 ms |
| Mute | 4395 ms | 390 ms |
| Camera off | Not measured | 508 ms |
| Camera on | Not measured | 495 ms |

These are process launch through confirmed JSON result timings, not visual frame timings. A second microphone check through the Node coordinator and the installed `0.2.0.4` helper completed unmute in 435 ms and the immediately following mute in 425 ms. Both commands were accepted without an added delay. The installed manifest, both binary hashes, and a new plugin process were verified.

The native regression fixture previously took 833 ms to parse a 1000-node meeting and failed its 250 ms budget; it now passes. Tests also cover batched missing/error attributes, fresh verification state, disappeared controls, and preserved ambiguity.

Physical Stream Deck key-to-frame timing, toolbar and focus variants, other languages, Leave safety, and reaction delivery after these optimizations remain unverified. Reactions benefit from faster scans and check for the picker immediately; their tap and hold behavior still needs live qualification on this build.

## 2026-10-28 persistent helper qualification

Implementation plan: [persistent controls](../plans/persistent-controls.md).
Final packaged version: `0.2.0.6`. Client remains Teams `26276.505.5234.9924`,
English UI, with an active meeting. Approved microphone/camera checks restored
their starting states: microphone unmuted, camera on. Leave was not pressed.

The persistent helper caches control references, compares process/window context,
and reads fresh attributes before each request. It observes Accessibility and
workspace changes, with debouncing and a two-second targeted fallback. Idle
observation pauses around hand, Leave, and reaction operations. The shared lock,
state confirmation, reaction cancellation, and five-second guard remain in place.

Measured results during implementation:

| Check | Result |
|---|---|
| Cold persistent status | 730 ms in the initial run |
| Warm persistent status | 17 to 50 ms initially; later checks 19 to 29 ms |
| Warm mute/camera command completion | 165 to 249 ms in the first six-command run |
| Focused microphone trace | Mute 125 ms; unmute 84 ms |
| Synchronous Accessibility press | Under 1 ms in the focused trace |
| State confirmation after press | 24 to 106 ms in the focused trace |
| External microphone changes through a separate helper | Observed at 480 and 386 ms from starting the external command, including its discovery cost |
| Explicit cache invalidation | Cold status 413 ms, then warm status 19 ms |
| Graceful stop followed by a new request | Fresh helper status completed in 362 ms |
| Ten-second idle sample | About 0.3% CPU, 12 MiB RSS, zero redundant state events |
| Closing stdin | Helper exited successfully without a diagnostic |

A local WebSocket fixture exercised the built plugin through actual SDK
`willAppear` and `keyDown` events against live Teams. Four consecutive microphone
presses reached confirmed state feedback in 247, 242, 150, and 46 ms. The microphone
returned to its starting state. Closing the simulated Stream Deck connection
stopped the plugin through its heartbeat after 6900 ms. These are simulated
event-to-feedback timings, not physical key-to-screen frame timings. The live
checks used the same cache/command paths before the final Node restart guards.

The under-100-ms target is not consistently achieved. Removing discovery makes
warm requests much cheaper, but Teams exposes changed state asynchronously and
confirmation latency varies. Cold discovery and invalidated contexts still take
hundreds of milliseconds. Keep those limits distinct from the warm state-read
timings.

Automated coverage includes allowed commands, bounded and fragmented protocol
messages, correlation/generation validation, stale event rejection, context and
control invalidation predicates, preserved ambiguity, shared locking, missing
key-up, timeout termination and forced kill, crash recovery without replay,
visibility ownership, ephemeral Multi Actions, connection heartbeat loss, and
restart races. Native tests, all 34 Node tests, TypeScript checking, build,
packaging, and package validation passed.

Installed `0.2.0.6` was verified against the rebuilt manifest version and both
binary hashes. New plugin PID 56591 owned helper PID 56601; both remained stable
across a nine-second heartbeat check with the real Stream Deck application.

Still unverified live: physical Stream Deck timing, prolonged idle/soak behavior,
multiple devices and real profile/device disconnects, Teams relaunch and meeting
transitions, sleep/wake, minimized/compact/multiple windows and focus variants,
other languages, Leave safety, and reaction delivery and hold lifecycle on this
build. Synthetic invalidation and lifecycle tests do not qualify those live cases.

## 2026-10-28 reaction ambiguity follow-up

Installed `0.2.0.6` logs showed successful microphone/camera commands and ten
successful reaction taps, followed by repeated reaction exit code 11 failures.
The original plugin and persistent helper were still alive during diagnosis.
Three read-only inspections reproduced two false reaction candidates: native
recent-item menu entries. No actual microphone, camera, or hand controls were
exposed at inspection time, despite Teams having windows. This does not establish
whether the meeting was still open when the original failure occurred.

Version `0.2.0.7` requires matching reaction action labels and rejects menu items
and unsafe chat contexts. Native regression fixtures cover two recent items
containing reaction words, a menu item named React, and false active-meeting
detection. The fixtures failed before the change and passed afterward. Existing
exact meeting React and custom-description hand-state cases still pass.

At that stage the original all-buttons symptom remained unresolved. The user
subsequently confirmed the meeting had remained open, initially in the background;
see the collision diagnosis below. Leave was not pressed, and
reaction delivery, repeated taps/holds in a live meeting, focus/window variants,
and prolonged operation remain unverified for this follow-up.

The original read-only reproduction was rerun against the rebuilt helper: no
false controls were reported and `meetingActive` was false. All 34 Node tests,
native tests, TypeScript checking, packaging, and validation passed. Installed
version `0.2.0.7` and both installed binary hashes match the rebuilt bundle.

## 2026-10-28 Accessibility identity collision fix

Version `0.2.0.8` fixes the missing-toolbar cause of the all-buttons failure.
The user confirmed the meeting stayed open. Bringing it forward did not fix
discovery. A same-window comparison found 66 elements with hash-only visitation
and 107 with full element identity comparison. Six unequal elements in that
window shared hashes; skipping a toolbar ancestor hid microphone, camera, and
React. The main Teams window also contained a collision.

Traversal now keeps the actual elements in its visited set, using equality to
distinguish hash collisions while still detecting cycles. Initial popup identity
sets for reaction and effect discovery use the same complete identities. Exact
control scoring, ambiguity rejection, command allow-listing, operation locking,
and reaction session guards remain intact.

A regression fixture runs the real traversal with six distinct elements sharing
one hash, a toolbar with microphone/camera/React descendants, and a cycle back to
the root. It failed before the correction and passed afterward, including the
state and React-discovery assertions. Three live read-only inspections then
consistently found microphone, camera, React, and Leave controls.

With Finder active and Teams in the background, three forced discovery requests
found the meeting. Approved microphone mute/unmute and camera off/on checks
confirmed each requested state and restored microphone unmuted and camera on.
Command completion times were 158, 377, 297, and 442 ms respectively. These are
helper confirmation timings, not physical key-to-frame measurements.

Leave was not pressed. Second-participant reaction delivery, repeated tap/hold
soaks, minimized/compact and multiple meeting windows, sleep/wake, and real
profile/device disconnects remain unverified on this build.

An initial background reaction tap was accepted but its immediate status read
contained only hand state, indicating the picker had not closed. Later direct
cleanup checks and a strict Node rerun passed. Cleanup now checks fresh attributes
on a cached reaction/hand target after Escape and retries only while that
confirmed picker control remains present, with a three-attempt bound. Tests
cover an ignored first Escape, successful dismissal, and the retry limit; the
ignored-dismissal fixtures failed before the change. No full-tree scan or focus
change was added to cleanup.

The final background Node check paused the persistent helper, accepted exactly
one Love reaction, resumed observation, and confirmed microphone unmuted and
camera on immediately afterward. Fifty consecutive status requests, including
five forced rediscoveries, passed after cleanup; median request time was 21 ms
and maximum 516 ms. Native regressions, all 34 Node tests, TypeScript checking,
packaging, and validation passed. Physical Stream Deck presses and extended
reaction soaks remain unverified.

Installed `0.2.0.8` was verified against the manifest and both rebuilt binary
hashes after completing Stream Deck's Install prompt. Stream Deck started a new
plugin process, PID 89177.
