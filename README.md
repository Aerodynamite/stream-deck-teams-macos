# Teams Reaction POC for macOS

This is a small proof of concept for pressing Microsoft Teams meeting reactions through the native macOS Accessibility API. It does not use the retired Teams third-party API, mouse coordinates, screenshots, or image recognition.

It supports the five standard Teams reactions:

- `like`
- `love`
- `applause`
- `laugh`
- `surprise`

## Requirements

- macOS with Xcode Command Line Tools installed
- The current Microsoft Teams desktop application
- A Terminal application with Accessibility permission

## Build

Open Terminal in this directory and run:

```sh
./build.sh
```

The compiled binary is written to `.build/teams-reaction`.

Run the launcher-selection regression test with:

```sh
./test.sh
```

It verifies that the meeting `React` button is preferred over both `Raise your hand` and a chat-message reaction button.

## First test: inspect without clicking

1. Start Microsoft Teams.
2. Join a test meeting.
3. Make sure the meeting controls are visible.
4. Run:

```sh
./.build/teams-reaction inspect
```

On first use, macOS should ask for Accessibility access. Under the following location, enable the new `teams-reaction` entry or the Terminal application running it, whichever macOS displays:

`System Settings > Privacy & Security > Accessibility`

Quit and reopen Terminal after granting permission. Then rerun the command. Avoid rebuilding the binary between granting permission and testing because macOS can treat a rebuilt ad-hoc-signed executable as a new program.

`inspect` does not click anything. A successful result should include a reaction-menu candidate such as `React`, `Reactions`, or `React or raise your hand`.

The inspection output can include accessible window and control labels. Review it before sharing it because a meeting title or participant name might appear.

## Send a reaction

While still in the meeting, run one of:

```sh
./.build/teams-reaction like
./.build/teams-reaction love
./.build/teams-reaction applause
./.build/teams-reaction laugh
./.build/teams-reaction surprise
```

The tool reports success only when macOS accepted both accessibility actions. Confirm that the reaction visibly appeared in Teams. For the strongest verification, use a second participant or device and check that it saw the reaction.

## Suggested verification sequence

1. Run `inspect` during a meeting and confirm it finds the reaction menu.
2. Send `like` while Teams is in front.
3. Send `applause` while Terminal is in front.
4. Ask another participant to confirm both reactions.
5. Try all five reactions.

## Expected limitations

- Teams may expose different labels in languages not included in the small synonym list.
- An organizer or administrator can disable live reactions.
- Teams interface updates can change accessible identifiers or labels.
- Multiple simultaneous Teams meeting windows have not been qualified by this POC.
- A successful Accessibility call proves that Teams accepted the UI action locally, not that the Teams service delivered it to other participants.

If `inspect` sees meeting buttons but does not recognize the reaction control, save its output locally. That will show which label or accessibility identifier needs to be added without requiring a larger application.
