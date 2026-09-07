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

For each rate, hold Love for three seconds. Count the values separately. The helper's Accessibility count is not a delivery count.

| Attempts per second | Scheduled attempts | Accessibility accepted | Seen by second participant | Teams responsive | Result |
|---:|---:|---:|---:|---|---|
| 1 | Not run | Not run | Not run | Not run | Not run |
| 2 | Not run | Not run | Not run | Not run | Not run |
| 3 | Not run | Not run | Not run | Not run | Not run |
| 5 | Not run | Not run | Not run | Not run | Not run |
| 10 | Not run | Not run | Not run | Not run | Not run |

Also verify:

- A tap sends exactly one reaction.
- Repeating starts only after the hold threshold.
- Release stops within one in-flight attempt.
- Holding beyond three seconds stops at the duration guard.
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

Do not call the plugin production-ready until all core controls pass in both directions, Leave is proven safe for attendee and organizer roles, and the default 3-per-second reaction wave is confirmed by a second participant.
