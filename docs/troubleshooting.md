# Installation and troubleshooting

For the normal setup flow, start with the [README](../README.md#installation).
For source builds and development links, see [Development](development.md).

## Install the packaged plugin

1. Keep Stream Deck open.
2. In Finder, double-click `teams-reactions/release/com.laurens-bolle.teams-reactions.streamDeckPlugin`.
3. Accept Stream Deck's installation prompt.
4. Find the **Teams Meeting Controls** category.
5. Add the controls you want to a Stream Deck profile.

For a normal update, install a package with a higher version over the existing plugin. Existing keys update automatically and keep their mappings; you do not need to drag the actions onto the deck again. If a separately linked development copy conflicts with package installation, remove that development link first.

## Reload after updating the plugin

Stream Deck keeps the plugin process from the last install running. Copying a new `bin/plugin.js` into the installed plugin folder does not reload it, and `streamdeck restart` is ignored for a plugin that was installed from a package rather than linked in developer mode. To load a new build, either:

- Install a repacked `.streamDeckPlugin` with a higher manifest `Version`, or
- Quit Stream Deck from its menu bar icon and reopen it.

Bump the manifest version before packaging an update. Stream Deck can reject an installer with the same version as already installed, leaving the old files in place. Restarting alone only helps if the installed files have actually been replaced. Verify the installed manifest version and compare both installed `bin/plugin.js` and `bin/teams-reaction` with the rebuilt files before treating an update as loaded.

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

See the [live qualification checklist](testing/teams-call-controls.md) for the complete test matrix and recorded results.
