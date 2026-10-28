# Teams Meeting Controls for Stream Deck

Control a Microsoft Teams meeting from your Stream Deck on macOS: mute or unmute,
toggle the camera, raise or lower your hand, leave the call, and send Like, Love,
Applause, Laugh, or Surprise reactions.

The plugin uses macOS Accessibility. It needs no Teams credentials, network API,
or separate companion application.

## Requirements

- macOS 13 or newer, with an Apple silicon Mac for the current packaged build
- Stream Deck 7.1 or newer
- Microsoft Teams desktop (`com.microsoft.teams2`)

## Installation

1. Keep Stream Deck open and double-click the `.streamDeckPlugin` package.
2. Accept the installation prompt, then find **Teams Meeting Controls** and add
   the actions you want to your profile.
3. Join a test meeting and try a control. If macOS requests Accessibility access,
   enable the entry it presents under **System Settings > Privacy & Security >
   Accessibility**, then quit and reopen Stream Deck.

To build the package from source:

```sh
cd teams-reactions
npm ci
npm test
npm run pack
```

The package is written to
`teams-reactions/release/com.laurens-bolle.teams-reactions.streamDeckPlugin`.
See [Development](docs/development.md) for build requirements and validation.

For updates, install a package with a higher version. **Existing keys update
without remapping.** A same-version installer can be rejected as already installed.
See [Installation and troubleshooting](docs/troubleshooting.md) for reloads,
permission issues, and update verification.

## Using the controls

Mute, camera, and hand keys show the state reported by Teams. Unknown or unavailable
states have distinct icons. A green check confirms the requested state, or that
Accessibility accepted a reaction. A yellow alert means the control is unavailable,
ambiguous, busy, or failed.

- Tap a reaction key to send once.
- Hold it to repeat at 7 attempts per second, starting after about 300 ms.
- Release to stop. Each hold is limited to five seconds, including picker setup.
- Reactions in Multi Actions send once. Only one Teams operation runs at a time.

Reaction acceptance does not prove delivery to another participant. Test **Leave
Call** in a disposable meeting before relying on it.

## Status

Version `0.2.0.8` keeps microphone and camera controls responsive with a persistent
native helper and fixes missing controls caused by Accessibility hash collisions.
Live checks confirmed microphone and camera changes and a reaction tap with Teams
in the background; earlier helper checks confirmed both hand commands.

Leave safety, minimized/compact and multiple meeting windows, extended reaction
holds on this build, and delivery to another participant still need qualification.
See the [testing checklist and results](docs/testing/teams-call-controls.md) for
measurements and the full list of verified and unverified cases.

## Documentation

- [Development](docs/development.md): builds, packaging, tests, helper commands, and shortcut experiments
- [Architecture](docs/architecture.md): helper lifecycle, control discovery, reaction sessions, and protocol
- [Installation and troubleshooting](docs/troubleshooting.md): permissions, reloads, and update verification
- [Design research](docs/research/teams-call-controls.md): alternatives and technical decisions
