# Teams Reactions for Stream Deck

A macOS Stream Deck plugin for sending Microsoft Teams meeting reactions through the native Accessibility API. It provides five separate keypad actions:

- Like
- Love
- Applause
- Laugh
- Surprise

The plugin does not use mouse coordinates, screen capture, image recognition, Teams account credentials, or a network API. Each key press starts the bundled native helper, sends one allow-listed reaction command, and lets the helper exit.

## Current status

This is a local development build for Apple silicon Macs. The native reaction path has worked in a live Teams meeting, and the plugin package passes automated and manifest validation. The remaining hands-on milestone is confirming which executable macOS shows in Accessibility settings when Stream Deck launches the bundled helper.

The plugin identifier `com.laurens-bolle.teams-reactions` and author metadata are development values. Confirm them before publishing. The helper is ad-hoc signed and the package is not notarized.

## Requirements

- macOS 13 or newer
- Apple silicon Mac
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

`npm run pack` rebuilds both the Objective-C helper and the Node plugin before packaging them together. No companion application, daemon, or service is required.

## Install the packaged plugin

1. Keep the Stream Deck application open.
2. In Finder, double-click `teams-reactions/release/com.laurens-bolle.teams-reactions.streamDeckPlugin`.
3. Accept Stream Deck's installation prompt.
4. In Stream Deck, find the **Teams Reactions** category.
5. Drag the **Love** action onto a key for the first live test.

If an older development copy with the same plugin identifier is already installed or linked, remove it in Stream Deck before installing the package.

The Stream Deck packer stores every file in the archive without an execute bit, so the installed `bin/teams-reaction` helper arrives as a plain 0644 file. The plugin restores the execute bit itself before each launch, so no manual `chmod` is needed after installation.

## Test in a Teams meeting

1. Join a test meeting in the Microsoft Teams desktop application.
2. Keep the meeting controls visible so Teams exposes its **React** button.
3. Press the Stream Deck **Love** key once.
4. On first use, macOS may open **System Settings > Privacy & Security > Accessibility**.
5. Enable whichever entry macOS presents, expected to be `teams-reaction` or Stream Deck.
6. Quit and reopen Stream Deck after changing the permission.
7. Return to the meeting and press **Love** again.
8. Confirm the heart appears in Teams. For delivery validation, have another participant or device confirm that it saw the reaction.

A green check on the Stream Deck key means macOS accepted both Accessibility actions. It does not prove that the Teams service delivered the reaction. A yellow alert means the helper failed, timed out, or another reaction was already running.

After Love works, add and test Like, Applause, Laugh, and Surprise. Pressing two reaction keys rapidly should never start overlapping helper processes. The second key press shows an alert while the first reaction is still running.

## Test expected failures

These checks verify Stream Deck feedback and local diagnostics:

1. Quit Teams, then press a reaction key. The key should show an alert.
2. Temporarily disable the relevant Accessibility permission, then press a key. The key should show an alert and macOS may prompt again.
3. Open Teams without joining a meeting, then press a key. The key should show an alert because no safe meeting reaction control is available.

The plugin logs only reaction names, exit codes, and privacy-safe diagnostics. It does not log helper stdout, meeting titles, or participant names.

For a development link, logs are normally written under:

```text
teams-reactions/com.laurens-bolle.teams-reactions.sdPlugin/logs/
```

For a packaged installation, look under:

```text
~/Library/Application Support/com.elgato.StreamDeck/Plugins/com.laurens-bolle.teams-reactions.sdPlugin/logs/
```

## Development mode

To link this checkout directly into Stream Deck:

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
npm test          # native launcher regression, Node tests, and TypeScript check
npm run build     # native helper plus bundled Node plugin
npm run validate  # official Elgato manifest and asset validation
npm run pack      # validated .streamDeckPlugin artifact
```

The native helper can still be exercised independently from the repository root:

```sh
./test.sh
./build.sh
./.build/teams-reaction inspect
./.build/teams-reaction love
```

`inspect` does not press a control, but its output can contain accessible window labels. Review that output before sharing it.

## Architecture

```text
Stream Deck key
    -> Node.js Stream Deck SDK action
    -> execFile("teams-reaction", [reaction])
    -> macOS AXUIElement traversal
    -> Teams meeting React button
    -> requested reaction
```

The Node layer uses `execFile` with exactly one allow-listed argument, a six-second timeout, privacy-safe error mapping, success and alert feedback, and a shared execution lock. The Objective-C helper retains the tested selection rule that prefers the meeting **React** control over **Raise your hand** and **React to this message**.

See [PLUGIN_HANDOFF.md](PLUGIN_HANDOFF.md) for the feasibility evidence, Accessibility behavior, exit-code contract, and known qualification gaps that preceded the plugin implementation.
