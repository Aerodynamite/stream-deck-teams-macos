# macOS Teams Reactions Stream Deck Plugin Handoff

Date: 2026-09-01

## Objective

Build a macOS Stream Deck plugin that sends Microsoft Teams meeting reactions. Reactions are the primary feature. A native proof of concept in this repository has already sent a reaction successfully in a live Teams meeting.

This document is intended to give a new Codex session enough context to begin implementation without repeating the feasibility research or rediscovering the accessibility behavior.

## Proven result

The critical path is feasible and has been tested locally:

```text
Stream Deck action
    -> macOS native helper
    -> Teams accessibility tree
    -> React button
    -> reaction popover
    -> requested reaction button
```

The user ran the compiled helper manually from Terminal while in a Teams meeting. After one launcher-selection bug was corrected, the user confirmed that the reaction worked.

Observed environment:

- Microsoft Teams bundle identifier: `com.microsoft.teams2`
- Microsoft Teams version observed during research: `26213.1006.5011.1671`
- Stream Deck version observed during research: `7.5.1`
- Machine architecture used by the POC: Apple silicon, arm64
- Teams accessibility scan found 6 matching processes and 706 accessible elements during the live meeting

The live meeting window was exposed as `Echo | Microsoft Teams`. Its relevant accessible controls were:

```text
role=AXButton actions=AXPress,AXShowMenu,AXScrollToVisible
Raise your hand

role=AXButton actions=AXPress,AXShowMenu,AXScrollToVisible
React
```

This confirms that current Teams exposes the meeting reaction control as an actionable macOS accessibility button.

## Current repository contents

- `TeamsReactionPOC.m`: native macOS accessibility implementation
- `build.sh`: builds and ad-hoc signs the helper
- `test.sh`: builds and runs launcher-selection regression tests
- `tests/LauncherScoringTests.m`: fixture reproducing the live accessibility-tree bug
- `README.md`: manual build and meeting-test instructions
- `.build/teams-reaction`: compiled helper, intentionally ignored by Git

The repository was otherwise empty when the POC was created. All current source files are uncommitted unless the user has committed them since this handoff was written.

## Build and verification commands

Build the native helper:

```sh
./build.sh
```

Run the deterministic regression test:

```sh
./test.sh
```

Expected test output:

```text
PASS: selected the exact meeting React control
```

Inspect Teams without pressing anything:

```sh
./.build/teams-reaction inspect
```

Send a reaction:

```sh
./.build/teams-reaction like
./.build/teams-reaction love
./.build/teams-reaction applause
./.build/teams-reaction laugh
./.build/teams-reaction surprise
```

The source compiles cleanly with `-Wall -Wextra`. Clang static analysis completed without code findings. The binary is ad-hoc signed with the stable development identifier `com.local.TeamsReactionPOC`.

## Accessibility implementation

The helper uses `AXUIElement` through the macOS ApplicationServices framework. It does not use:

- Mouse coordinates
- Screen recording
- Image recognition
- AppleScript menu clicking
- DOM injection
- The retired Teams third-party API

### Process discovery

`CandidateApplications()` enumerates `NSWorkspace.sharedWorkspace.runningApplications` and selects Teams processes using bundle identifiers, application names, and executable names. This intentionally includes Teams helper processes when macOS registers them as running applications.

Before scanning, `EncourageAccessibilityTree()` makes best-effort requests for:

- `AXManualAccessibility`
- `AXEnhancedUserInterface`

Unsupported attributes are harmless and return an accessibility error that is ignored.

### Tree traversal

The helper:

1. Gets each Teams process accessibility root.
2. Gets its focused window and window list.
3. Traverses `AXChildren` to a maximum depth of 40.
4. Limits a traversal to 30,000 elements.
5. Captures role, identifier, title, description, help, value, actions, depth, process, and window information.
6. Selects only actionable candidates.

### Reaction flow

`SendReaction()` performs this sequence:

1. Scan Teams.
2. Select the best reaction-menu launcher.
3. Invoke `AXPress`, falling back to `AXShowMenu` if needed.
4. Poll the Teams accessibility trees every 120 milliseconds for up to 4 seconds.
5. Prefer reaction elements that appeared after the menu was opened.
6. Select the requested semantic reaction.
7. Invoke `AXPress` on the reaction.
8. Report that both accessibility actions were accepted.

The helper does not claim server-side delivery. For definitive delivery validation, use another meeting participant or device.

### Supported reaction labels

The command vocabulary is fixed to five canonical actions:

- `like`
- `love`
- `applause`
- `laugh`
- `surprise`

The matching logic includes a small set of English, Dutch, German, French, and Spanish synonyms. It includes Teams label variants such as heart, clap, and wow. This is a starter catalog, not fully qualified localization support.

## Resolved launcher-selection bug

The first live attempt failed in a useful way:

```text
Best reaction-menu candidate:
Raise your hand
```

Running `love` then raised the user's hand instead of opening the React popover.

Root cause:

- `Raise your hand` was incorrectly included in the reaction-launcher synonym list.
- The scoring function also gave hand-raising text a 25-point bonus.
- In the captured fixture, `Raise your hand` scored 120 while `React` scored 95.

The regression fixture was created before changing the implementation. It reproduced two unsafe selections:

```text
FAIL: expected React, selected Raise your hand (Raise=120, React=95)
FAIL: expected meeting React, selected React to this message (Chat=98, Meeting=95)
```

The fix:

- Removed all pure hand-raising phrases from launcher matching.
- Added a strong bonus for an exact localized reaction-launcher label.
- Added a penalty for controls referring to a chat or message.
- Retained an identifier bonus when an accessibility identifier contains `react`.

The test now consistently selects the exact meeting `React` button over both `Raise your hand` and `React to this message`.

Do not remove or bypass this regression test while integrating the helper into the plugin.

## Exit-code contract

The Stream Deck layer can use the helper's exit status as its first integration contract:

| Code | Meaning |
|---:|---|
| 0 | Accessibility accepted the requested operation |
| 1 | Accessibility permission is missing |
| 2 | Teams is not running |
| 3 | No safe reaction-menu launcher was found |
| 4 | The reaction-menu launcher could not be invoked |
| 5 | The requested reaction was not found before timeout |
| 6 | The reaction element could not be invoked |
| 64 | Invalid command or arguments |

Diagnostics are written to standard error. Normal progress and success messages are written to standard output.

For the first plugin version:

- Exit 0 should call the Stream Deck success feedback API.
- Any nonzero exit should call the Stream Deck alert feedback API.
- Standard error should be written to the plugin log.
- Do not place meeting titles or participant names on Stream Deck button titles or in telemetry.

## Recommended plugin architecture

Use the current official Node.js Stream Deck SDK for the plugin and keep the accessibility code in the native helper:

```text
*.sdPlugin/
├── manifest.json
├── bin/
│   ├── plugin.js
│   └── teams-reaction
└── imgs/
    ├── plugin icons
    └── five reaction action icons
```

The Node plugin should launch the bundled helper with `child_process.execFile()` and pass exactly one allow-listed reaction argument. Do not construct a shell command.

### Process lifecycle and installation model

The first version should be one installable `.streamDeckPlugin` artifact. It should not require the user to install or keep a separate application running.

Expected lifecycle:

1. Stream Deck starts and manages the normal Node plugin process.
2. No separate Teams-reaction service is started.
3. A reaction key press launches the bundled `teams-reaction` helper.
4. The helper performs one reaction and exits immediately.
5. When Stream Deck is closed, neither the plugin nor the reaction helper remains running.

This design requires no daemon, menu-bar application, login item, persistent local server, or separately managed background service. The Node plugin process remains active while Stream Deck is open because that is the normal Stream Deck plugin lifecycle, not an additional user-installed service.

The helper should normally live inside the plugin directory and run only on demand. A long-running helper is unnecessary for the first version because the proven accessibility scan and reaction flow complete within one command invocation.

This is the smallest route because:

- The official TypeScript SDK handles Stream Deck WebSocket registration and action events.
- The working Objective-C accessibility engine remains isolated and testable.
- Rewriting the plugin as a native WebSocket client adds work without improving the reaction proof.
- A Node native addon is not necessary for the first version.

Elgato currently recommends SDK version 3, Node.js 24, Stream Deck 7.1 or newer, and the official Stream Deck CLI. The manifest supports a macOS-only entry and application monitoring. See:

- [Elgato getting started](https://docs.elgato.com/streamdeck/sdk/introduction/getting-started/)
- [Elgato manifest reference](https://docs.elgato.com/streamdeck/sdk/references/manifest/)
- [Elgato Stream Deck CLI](https://docs.elgato.com/streamdeck/cli/intro/)
- [Elgato native plugin reference](https://docs.elgato.com/streamdeck/sdk/references/websocket/plugin/)

The native plugin reference calls direct native WebSocket plugins an advanced technique and recommends the Node.js SDK path. That supports using a Node plugin plus native helper here.

## Suggested first plugin scope

Keep the first plugin deliberately narrow:

- Five independent keypad actions: Like, Love, Applause, Laugh, Surprise
- macOS only
- No property inspector
- No account, token, pairing, or network API
- No mute, camera, leave, or other Teams controls yet
- Success and failure feedback on the Stream Deck key
- Serialized execution so two reaction popovers cannot overlap
- A short timeout around each helper invocation
- Local diagnostic logging

Five independent actions are simpler than one configurable action and make the initial profile obvious. A configurable reaction action can be added later if desired.

### Suggested action behavior

For each action's key-down event:

1. Reject or queue the event if another reaction is running.
2. Resolve the helper path relative to the plugin directory.
3. Call `execFile(helperPath, [reaction])` with no shell.
4. Apply a timeout slightly longer than the helper's four-second menu timeout, such as six seconds.
5. On exit 0, show success feedback.
6. On a nonzero exit, log the code and sanitized error, then show alert feedback.
7. Release the execution lock in a `finally` block.

Do not send a reaction on both key-down and key-up. Use one event only.

## Manifest direction

Use a unique reverse-DNS plugin UUID chosen with the user. Do not publish with the temporary helper identifier.

Recommended manifest properties:

- `SDKVersion`: `3`
- `Nodejs.Version`: `24`
- `Software.MinimumVersion`: `7.1`
- `OS`: macOS only for the first release
- `OS.MinimumVersion`: decide after testing, with macOS 13 as a reasonable starting point
- `ApplicationsToMonitor.mac`: `com.microsoft.teams2`
- Five actions with stable, unique UUIDs
- Keypad controller support
- `DisableAutomaticStates`: true unless actual state tracking is added

Do not invent the final author name, organization identifier, or public plugin UUID without asking the user.

## Accessibility permission risk

The main remaining integration risk is not reaction selection. It is how macOS attributes Accessibility permission when Stream Deck launches the bundled helper.

The manual POC calls `AXIsProcessTrustedWithOptions()` with prompting enabled. During direct Terminal testing, macOS may show either the helper or the terminal application in:

`System Settings > Privacy & Security > Accessibility`

The plugin integration must test what appears when Stream Deck launches the helper. Possible outcomes:

1. The helper appears and can be enabled directly.
2. Stream Deck appears as the responsible application.
3. An ad-hoc-signed helper loses trust after each rebuild.

For local development, keep the helper path and signing identifier stable. If permission becomes stale, remove and re-add the relevant entry.

For a polished distribution, likely options are:

- Sign the helper with a stable Developer ID identity and bundle identifier.
- Package a small companion `.app` in `/Applications` and communicate with it through a local IPC mechanism.
- Keep the helper embedded only if signing and TCC behavior remain stable after plugin updates.

A companion application is a contingency, not part of the intended first architecture. Add one only if a signed helper embedded in the plugin cannot retain Accessibility permission reliably across restarts and plugin updates. Do not choose the companion-app architecture until that direct bundled-helper experiment has failed with clear evidence.

## Toolchain note

The first implementation was attempted in Swift, but this machine's selected Command Line Tools were inconsistent:

- Swift compiler: 6.3.3
- macOS SDK Swift interfaces: 6.3.2

That prevented Swift module compilation. The POC was rewritten in Objective-C and compiles successfully with Clang, Foundation, AppKit, and ApplicationServices.

Do not spend time converting it back to Swift during initial plugin integration. The current source works and isolates the platform API cleanly. A later conversion is optional after the local Xcode toolchain is repaired.

## Known gaps

The following are not yet qualified:

- All five reactions in repeated live tests
- Non-English Teams interfaces in live meetings
- Multiple simultaneous Teams meeting or popout windows
- Meetings where the organizer or policy disables reactions
- Teams minimized, hidden, or under screen sharing
- Rapid repeated key presses
- Reaction delivery as observed by a second participant
- Accessibility permission when the helper is launched by Stream Deck
- Intel Mac or universal-binary support
- Signed and notarized distribution
- Behavior after a Teams update changes accessibility identifiers or labels
- Custom or branded Teams reactions

The current result proves feasibility, not production reliability.

## Recommended implementation sequence

1. Run `./test.sh` and `./build.sh` to establish the existing green baseline.
2. Inspect the repository and preserve the working helper behavior.
3. Verify Node.js 24 and install the current `@elgato/cli` only if missing.
4. Scaffold a new plugin with `streamdeck create` inside this repository.
5. Choose a temporary local plugin UUID only after checking with the user if identity matters.
6. Add one `Love` action first.
7. Bundle the existing helper and call it with `execFile()`.
8. Test the Love action in a real Teams meeting.
9. Record exactly which application or binary macOS requires in Accessibility settings.
10. Add the other four actions by reusing the same runner.
11. Add serialization, timeout handling, success feedback, alert feedback, and sanitized logs.
12. Run all five actions in a live meeting, including while Stream Deck is the invoking application.
13. Only then address icons, packaging, permanent signing, localization, and broader Teams controls.

## Acceptance criteria for the first plugin milestone

- A Stream Deck key sends the correct Love reaction in an active Teams meeting.
- No mouse movement or coordinate clicking occurs.
- The helper selects `React`, never `Raise your hand` or a message reaction.
- Missing permission, Teams not running, and no active meeting show alert feedback.
- The plugin does not start overlapping helper processes.
- Installation and normal use require no separate application, daemon, menu-bar process, or login item.
- The plugin log records exit code and sanitized diagnostics.
- The regression test remains green.
- The user confirms the reaction appeared in Teams.

Once that milestone is green, expanding from one reaction to five is low-risk repetition rather than new feasibility work.

## External feasibility context

The old Teams third-party device API is retired, so do not base new work on localhost pairing or Graph APIs. Microsoft Graph does not provide an endpoint for sending a live meeting-stage reaction.

Current commercial evidence also supports this architecture: MuteDeck reported moving its macOS Teams integration to native macOS Accessibility APIs and later shipping native-UI Teams reactions after the old API was deprecated.

References:

- [Elgato notice about the retired Microsoft Teams integration](https://help.elgato.com/hc/en-us/articles/26249796361613-How-to-pair-Stream-Deck-plugin-with-Microsoft-Teams)
- [MuteDeck 4.4 changelog](https://mutedeck.com/changelog/mutedeck-v44)
- [Microsoft live reactions guide](https://support.microsoft.com/en-us/teams/meetings/express-yourself-in-microsoft-teams-meetings-with-live-reactions)
- [Apple AXUIElement documentation](https://developer.apple.com/documentation/applicationservices/axuielement_h)

The local live-meeting result is stronger evidence for this project than the external product reports. The reaction feature works through the current Teams accessibility interface on this Mac.
