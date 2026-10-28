# Agent instructions

Use plain punctuation. No em-dashes in prose, comments, or documentation.

Read `README.md` before changing behavior or building. For control-selection or
reaction changes, follow `docs/testing/teams-call-controls.md` and report which
live cases remain unverified.

## Packaged plugin updates

1. Increase `Version` in
   `teams-reactions/com.laurens-bolle.teams-reactions.sdPlugin/manifest.json`
   above the installed version before packaging. Stream Deck can reject the same
   version as "already installed", leaving the old files in place.
2. Build, validate, and package using the README, then open the package and
   complete Stream Deck's installation prompt.
3. Verify the installed manifest version and compare installed `bin/plugin.js`
   and `bin/teams-reaction` with the rebuilt files. The installed bundle is under
   `~/Library/Application Support/com.elgato.StreamDeck/Plugins/com.laurens-bolle.teams-reactions.sdPlugin`.
4. Confirm a new plugin process started before reporting the update as loaded.
   Reinstalling or a full Stream Deck restart reloads replaced files; restarting
   alone cannot install files that the installer rejected.
