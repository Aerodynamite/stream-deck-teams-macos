# Teams Meeting Controls for Stream Deck

A self-contained macOS Stream Deck plugin for controlling an active Microsoft Teams meeting through the native Accessibility API.

The plugin provides these keypad actions:

- Mute or unmute
- Turn the camera on or off
- Raise or lower your hand
- Leave the call
- Like, Love, Applause, Laugh, and Surprise reactions
- A bounded reaction wave when a reaction key is held

The plugin does not use mouse coordinates, screen capture, image recognition, Teams account credentials, a network API, or a separate companion application. Stream Deck starts the bundled native helper only when an action or state refresh needs it.

## Current status

Version `0.2.0.3` implements the new actions, plugin-controlled two-state keys, explicit desired-state commands, JSON state results, control-specific safety rules, optional process-targeted keyboard fallbacks, and native long-press reaction sessions.

Automated tests cover command allow-listing, JSON validation, process locking, burst cancellation and timeout handling, exact control selection, state derivation, and the original regression that distinguishes the meeting **React** button from **Raise your hand** and **React to this message**.

The implementation still needs live qualification in real Teams meetings before it should be treated as production-ready. In particular:

- Exact microphone, camera, hand, and leave labels need confirmation against the installed Teams build.
- Keyboard fallbacks are compiled but disabled by default until they pass focus and minimized-window testing.
- Accessibility acceptance of repeated reactions does not prove that every reaction reached another participant.

## Teams toolbar compatibility

The helper reads Chromium's `AXCustomContent` descriptions as well as visible labels, and falls back to `AXDOMIdentifier` when `AXIdentifier` is absent. Teams can keep a short label such as `Raise` unchanged while its custom description switches between `Raise your hand` and `Lower your hand`.

The React control can expose hand state directly in its custom description. When a hand change needs the control inside React, the helper opens the picker and dismisses it afterward with Escape sent only to Teams. Reactions open React directly without scrolling first, since scrolling immediately before pressing can invalidate the new toolbar's action path. Hand changes have a 15-second helper timeout to allow the picker and state verification round trip. Meeting-control shortcut fallbacks remain disabled by default.

Live helper checks on Teams `26276.505.5234.9924` confirmed hand state and both hand commands. One Love reaction was accepted by Accessibility. Second-participant delivery and the remaining live matrix are still unverified.

## Requirements

- macOS 13 or newer
- Apple silicon Mac for the current packaged development build
- Stream Deck 7.1 or newer
- Microsoft Teams with bundle identifier `com.microsoft.teams2`
- Node.js 24 or newer when building from source
- Xcode Command Line Tools

## Build and package

From the repository root:

```sh
cd teams-reactions
npm ci
npm test
npm run build
npm run validate
npm run pack
```

The installable artifact is written to:

```text
teams-reactions/release/com.laurens-bolle.teams-reactions.streamDeckPlugin
```

`npm run pack` rebuilds both the Objective-C helper and the Node plugin before packaging them together.

Regenerate all reaction and meeting-control PNG assets after changing their SVG sources:

```sh
npm run build:icons
```

This requires `rsvg-convert` from librsvg.

## Install the packaged plugin

1. Keep Stream Deck open.
2. In Finder, double-click `teams-reactions/release/com.laurens-bolle.teams-reactions.streamDeckPlugin`.
3. Accept Stream Deck's installation prompt.
4. Find the **Teams Meeting Controls** category.
5. Add the controls you want to a Stream Deck profile.

If an older development copy with the same plugin identifier is installed or linked, remove it before installing the package.

## Reload after updating the plugin

Stream Deck keeps the plugin process from the last install running. Copying a new `bin/plugin.js` into the installed plugin folder does not reload it, and `streamdeck restart` is ignored for a plugin that was installed from a package rather than linked in developer mode. To load a new build, either:

- Install a repacked `.streamDeckPlugin` with a higher manifest `Version`, or
- Quit Stream Deck from its menu bar icon and reopen it.

Bump the manifest version before packaging an update. Stream Deck can reject an installer with the same version as already installed, leaving the old files in place. Restarting alone only helps if the installed files have actually been replaced.

After a reload, `~/Library/Logs/ElgatoStreamDeck/StreamDeck.log` shows a new `Plugin connected` line for `com.laurens-bolle.teams-reactions`.

The Stream Deck packer stores every file in the archive without an execute bit, so the installed `bin/teams-reaction` helper arrives as a plain 0644 file. The plugin restores the execute bit itself before each launch, so no manual `chmod` is needed after installation.

## First live test

1. Join a test meeting in the Microsoft Teams desktop application.
2. Keep the meeting controls visible for the first run.
3. Add **Mute**, **Camera**, **Raise Hand**, **Leave Call**, and **Love** to a test Stream Deck profile.
4. Press **Love** once.
5. On first use, macOS may open **System Settings > Privacy & Security > Accessibility**.
6. Enable the entry macOS presents, expected to be `teams-reaction` or Stream Deck.
7. Quit and reopen Stream Deck after changing the permission.
8. Verify each non-destructive control in both directions before testing **Leave Call**.
9. Test **Leave Call** in a disposable meeting. Confirm it leaves only the local participant and never ends the meeting for everyone.
10. Ask another participant or device to confirm reaction delivery.

A green check means the requested state was confirmed, or at least one reaction was accepted by Accessibility. A yellow alert means the state was unknown, the control was unavailable or ambiguous, another Teams operation was active, or the helper failed.

Unknown and unavailable control states are rendered with dedicated question-mark or unavailable images. The plugin does not map either condition to a confident on or off icon.

## Reaction key behavior

- A normal tap sends exactly one reaction.
- Holding longer than about 300 ms starts repeating at 7 attempts per second, reusing the open picker and cached reaction control.
- Releasing the key closes the helper's standard input and stops scheduling new attempts.
- A session stops after 5 seconds even if key-up is lost. This budget includes picker setup, so slow setup reduces the total number of reactions.
- Native hard limits cap the rate at 10 attempts per second and the session at 50 attempts.
- Only one Teams operation can run at a time.
- Reactions inside a Stream Deck Multi Action always send once because there is no physical hold duration.

Success feedback is shown once when the session ends. Logs contain only aggregate reaction type, attempt count, Accessibility acceptance count, elapsed time, and stop reason.

## Control state behavior

Mute, camera, and hand actions use two Stream Deck states with automatic state changes disabled. The plugin asks the helper for current state when an action appears and updates all visible control keys after every completed command.

Commands request an explicit result instead of blindly toggling:

```text
mute
unmute
camera-on
camera-off
hand-raise
hand-lower
leave
```

If a user changes Teams directly, the first plugin milestone does not receive that change in real time. The next Stream Deck state refresh or completed command reconciles the visible key. A later `AXObserver` child-process mode can add live synchronization without changing the command contract.

## Native helper commands

Build the standalone helper from the repository root:

```sh
./build.sh
```

Inspect known meeting controls without pressing anything:

```sh
./.build/teams-reaction inspect-controls
```

Query state or invoke explicit commands:

```sh
./.build/teams-reaction status
./.build/teams-reaction mute
./.build/teams-reaction unmute
./.build/teams-reaction camera-on
./.build/teams-reaction camera-off
./.build/teams-reaction hand-raise
./.build/teams-reaction hand-lower
./.build/teams-reaction leave
./.build/teams-reaction react love
./.build/teams-reaction burst love 7
```

Normal command results are one JSON object on standard output. Diagnostics go to standard error. `inspect-controls` omits meeting window titles, but its matched labels may still reflect the installed Teams language. Review diagnostic output before sharing it.

The native helper retains experimental `blur-on` and `blur-off` commands for research and manual testing. The packaged Stream Deck plugin does not expose a Background Blur action.

## Keyboard shortcut fallback

The helper includes process-targeted `Command+Shift+M`, `Command+Shift+O`, `Command+Shift+K`, and `Command+Shift+H` fallbacks for microphone, camera, hand, and leave. They are disabled by default because Teams allows shortcut customization and focus routing needs live qualification.

For a local terminal-only qualification run, enable individual families with a comma-separated environment variable:

```sh
TEAMS_CONTROLS_SHORTCUT_FALLBACK=microphone,camera,hand,leave ./.build/teams-reaction mute
```

Use `all` to enable every compiled fallback. Blur has no keyboard fallback because current Microsoft documentation is inconsistent about what its shortcut does.

## Development mode

Link this checkout directly into Stream Deck:

```sh
cd teams-reactions
npm ci
npm run build
npx streamdeck link com.laurens-bolle.teams-reactions.sdPlugin
npx streamdeck restart com.laurens-bolle.teams-reactions
```

For TypeScript development with automatic plugin restarts:

```sh
npm run watch
```

The native helper is rebuilt when watch mode starts. Restart watch mode after changing `TeamsReactionPOC.m`.

## Verification commands

```sh
cd teams-reactions
npm test
npm run build
npm run validate
npm run pack
```

The live qualification matrix and result fields are in [docs/testing/teams-call-controls.md](docs/testing/teams-call-controls.md). The design research and rejected alternatives are in [docs/research/teams-call-controls.md](docs/research/teams-call-controls.md).

## Architecture

```text
Stream Deck action
    -> allow-listed Node command and one global operation lock
    -> bundled teams-reaction helper
    -> strict per-control AXUIElement scorer
    -> AXPress and post-action state verification
    -> JSON result back to Stream Deck
```

Reaction holds use one child process for the complete key-down to key-up session. The helper opens the picker once and repeatedly presses the cached reaction element at roughly 143 ms intervals. Slow setup or recovery does not cause catch-up presses. It reopens and reacquires the picker only if the cached element becomes invalid, and dismisses the picker when the session ends. The original full Teams scan remains in the first reaction lookup so the proven popover path is not narrowed.

The native helper restricts process discovery to `com.microsoft.teams2` and its child bundle identifiers. Leave selection explicitly rejects end-meeting, end-for-all, decline, and dismiss controls. Equally plausible destructive controls fail as ambiguous instead of choosing one.
