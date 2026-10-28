# Persistent Teams controls

## Goal

Remove full Accessibility discovery from warm microphone and camera commands.
Target less than 100 ms from Node request to confirmed state in an active meeting.
Cold discovery, Teams animation, and replaced controls can still take longer.

## Implementation sequence

1. Add a native `serve` mode with bounded newline-delimited JSON requests and
   correlated responses. Allow only status, mute, unmute, camera-on, and camera-off.
   Keep ordinary one-shot commands available. Use one request at a time.
2. Retain discovered state controls. Before every warm request, compare the Teams
   process/window context and read current control attributes. Rediscover on
   invalid references, context changes, structural notifications, wake, or an
   explicit invalidation. Confirm state after pressing; never retry a press after
   uncertain completion. Leave always uses fresh discovery in its one-shot path.
3. Observe Accessibility and workspace changes. Debounce notifications and use
   cheap targeted state reconciliation as a fallback while controls are visible.
   Never continuously poll the full Accessibility tree. Publish validated state
   changes to the existing key synchronizer. Pause observation during one-shot
   operations and invalidate on resume.
4. Add a Node client behind the existing command coordinator. Preserve the shared
   operation lock and error/state distinctions. Retain the helper while control
   keys are visible, close stdin when no longer needed, and contain hangs with
   termination and kill watchdogs. EOF or parent death must stop the native loop.
   Fail a crashed request without replay; a later request can start a new helper.
5. Keep hand, Leave, and reaction operations on their existing one-shot paths.
   Preserve reaction release/disconnect cancellation and the five-second guard.
   Stop the persistent helper on plugin/device shutdown and invalidate on wake.
6. Test the protocol, fragmented/oversized output, command correlation, errors,
   timeout recovery, shutdown, context changes, invalid references, ambiguity,
   and mutual exclusion. Measure cold/warm timing and idle resource use. Build,
   validate, package with a higher version, install, and verify hashes/processes.

## Completion evidence

Record actual timings and live cases in `docs/testing/teams-call-controls.md`.
Measure command completion separately from physical key-to-frame timing. Restore
approved live microphone/camera changes to their starting states. Do not use the
real meeting for Leave tests. Mark unsupported notification and focus/window
cases as unverified. Keep meeting titles, participant names, and trees out of logs.

## Result

Implemented in version `0.2.0.6`. All six implementation steps are complete.
Native tests, 34 Node tests, TypeScript checking, packaging, and validation pass.
Read-only warm status measured 17 to 50 ms. Simulated Stream Deck microphone
presses measured 46 to 247 ms through confirmed SDK feedback. The under-100-ms
command target is not consistently met because Teams confirmation remains
asynchronous. Detailed evidence and unverified live cases are in the qualification
checklist linked above.
