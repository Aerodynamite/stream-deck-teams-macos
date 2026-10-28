# Development

Start each build, development-link, or verification sequence from the repository root.
The icon and watch commands run inside `teams-reactions`.
Building requires Node.js 24 or newer and Xcode Command Line Tools. The packaged
native helper currently targets Apple silicon.

## Build and package

From the repository root:

```sh
cd teams-reactions
npm ci
npm test
npm run pack
npm run validate
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

## Verification

`npm test` runs the native tests, Node tests, and TypeScript checking. Coverage
includes command allow-listing, state parsing, shared locking, process recovery,
reaction cancellation, Accessibility hash collisions, and bounded picker cleanup.
`npm run validate` checks the plugin manifest and package structure.

The [live qualification checklist](testing/teams-call-controls.md) records checks
that require an actual meeting, including timings and remaining gaps.

## Native helper commands

Return to the repository root before running these commands.

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

The persistent protocol is documented in [Architecture](architecture.md#persistent-protocol).

The native helper retains experimental `blur-on` and `blur-off` commands for research and manual testing. The packaged Stream Deck plugin does not expose a Background Blur action.

## Keyboard shortcut fallback

The helper includes process-targeted `Command+Shift+M`, `Command+Shift+O`, `Command+Shift+K`, and `Command+Shift+H` fallbacks for microphone, camera, hand, and leave. They are disabled by default because Teams allows shortcut customization and focus routing needs live qualification.

For a local terminal-only qualification run, enable individual families with a comma-separated environment variable:

```sh
TEAMS_CONTROLS_SHORTCUT_FALLBACK=microphone,camera,hand,leave ./.build/teams-reaction mute
```

Use `all` to enable every compiled fallback. Blur has no keyboard fallback because current Microsoft documentation is inconsistent about what its shortcut does.

See [Troubleshooting](troubleshooting.md) for packaged updates, reloads, and permission issues.
