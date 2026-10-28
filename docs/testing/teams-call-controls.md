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
