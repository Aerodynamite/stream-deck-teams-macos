# Research: Microsoft Teams call controls for Stream Deck on macOS

Date: 2026-09-02

## Implementation status

The recommended first milestone is implemented in plugin version `0.2.0.0`:

- Explicit status, microphone, camera, blur, hand, leave, and reaction commands return machine-readable JSON.
- Mute, camera, blur, and hand are plugin-controlled two-state Stream Deck actions. Leave is a separate safe action.
- Control-specific Accessibility scorers reject unsafe contexts and fail on equally plausible candidates.
- Leave selection explicitly rejects end-meeting, end-for-all, decline, and dismiss controls.
- Process-targeted keyboard fallbacks exist for microphone, camera, hand, and leave, but remain disabled until live qualification.
- Reaction keys use one bounded native child process from key-down through key-up, with a 300 ms hold threshold, a 3-attempt-per-second default, a 3-second duration guard, and hard limits of 10 attempts per second and 30 attempts.

Automated tests and package validation pass. Live Teams qualification remains open, including exact installed-client labels, blur state exposure, compact and hidden toolbars, shortcut focus behavior, organizer Leave safety, and second-participant reaction delivery. Track those results in [the live qualification checklist](../testing/teams-call-controls.md).

## Executive recommendation

Extend the existing Objective-C helper into a small Teams meeting-control backend.

Use two local control mechanisms:

1. Use macOS Accessibility (`AXUIElement`) as the primary mechanism. Find the active Teams meeting window, identify the exact semantic control, read its current state, and invoke `AXPress`.
2. Use a Teams keyboard shortcut posted directly to the Teams process with `CGEvent.postToPid` as a fallback when a toolbar control is temporarily absent or has moved.

Keep the existing Accessibility popover flow for individual reactions. Teams has no documented per-reaction keyboard shortcuts, and the former localhost third-party device API is no longer a viable option.

For reaction bursts, use a single native burst session that starts on Stream Deck key-down and stops on key-up. Do not launch a new helper process for every repeated reaction. A few reactions per second is a reasonable qualification target, but the current implementation cannot guarantee it and a 10-per-second rate is unproven through the Accessibility UI path.

Do not base new work on the retired Teams localhost API, Microsoft Graph calling APIs, or a Teams meeting app. None provides a supported way for this plugin to control the current signed-in user's native Teams meeting.

The recommended implementation remains self-contained inside the Stream Deck plugin. A companion application is not required for the first version.

## Why the former official plugin cannot be reproduced through its API

The official Microsoft Teams Stream Deck plugin used Teams' local third-party meeting and call control integration. Elgato removed the plugin from Marketplace on 2025-12-12 and states that Microsoft took the required API offline, so existing Teams actions stopped working. See [Elgato's pairing article and retirement notice](https://help.elgato.com/hc/en-us/articles/26249796361613-How-to-pair-Stream-Deck-plugin-with-Microsoft-Teams).

Microsoft Message Center notice MC1266901 described the integration as a limited, non-published capability and set its final retirement date to 2026-06-30. It also said the related Teams privacy setting would be removed. The original notice is tenant-only, but its contents are preserved in the [MC1266901 archive](https://mc.merill.net/message/MC1266901).

Microsoft's older [third-party device pairing support page](https://support.microsoft.com/en-us/teams/calls-devices/connect-to-third-party-devices-in-microsoft-teams) is still online and still describes `Settings > Privacy > Manage API`. It conflicts with the later retirement notice and Elgato's current statement. It should be treated as stale instructions, not evidence that the API is available in current Teams clients.

Consequences for this project:

- Do not reconnect to or reverse engineer the old localhost WebSocket service.
- Do not ask users for the old API token or pairing permission.
- Do not retain an API implementation as a fallback. The retirement date has passed, and the implementation would depend on a deliberately retired, unpublished interface.

## Existing implementation and local evidence

The current project already has the right macOS foundation:

```text
Stream Deck action
    -> Node plugin
    -> bundled Objective-C helper
    -> Teams AXUIElement tree
    -> AXPress on a semantic Teams control
```

The helper in [TeamsReactionPOC.m](../../TeamsReactionPOC.m) discovers Teams processes, walks the Accessibility tree, scores controls by role, identifier, localized text, meeting window, and action support, then calls `AXUIElementPerformAction`. It does not use coordinates, screenshots, image recognition, or a network service.

This path has been verified locally for reactions in a live meeting with Teams `26213.1006.5011.1671`. The live tree exposed `Raise your hand` and `React` as pressable `AXButton` elements. The current helper correctly distinguishes the meeting `React` button from `Raise your hand` and `React to this message`. See [PLUGIN_HANDOFF.md](../../PLUGIN_HANDOFF.md) for the captured evidence and regression history.

What is proven:

- Teams meeting controls can be discovered and pressed through macOS Accessibility.
- The bundled helper model works with the Stream Deck plugin.
- A live Teams meeting exposed a direct `Raise your hand` control.

What is not yet proven:

- The exact accessible labels, identifiers, and state attributes for microphone, camera, blur, lower hand, and leave.
- Operation when the meeting toolbar is hidden, Teams is minimized, or the compact sharing toolbar is active.
- Reliable state synchronization when a user changes a control inside Teams or from another device.
- Background blur navigation in the installed work or school Teams client.

## Options assessed

| Option | Requested controls | State feedback | Main advantages | Main problems | Verdict |
|---|---|---|---|---|---|
| Direct `AXUIElement` control | All five, plus reactions | Possible | Already proven locally, no focus stealing, can inspect semantic state, no account or network API | UI labels and structure can change, localized matching is needed, hidden toolbars require handling | Primary mechanism |
| Process-targeted keyboard shortcuts | Mute, camera, hand, leave; blur requires qualification | Not by itself | Small implementation, independent of control layout and language, can target Teams by PID | Users can customize shortcuts, Teams can suppress shortcuts in some focused views, blur shortcut documentation is inconsistent | Fallback and proof-of-concept path |
| Stream Deck built-in Hotkey or AppleScript keystrokes | Same as keyboard shortcuts | No | Very quick manual workaround | Normally reaches the foreground app, may steal focus, adds no state, AppleScript is only another wrapper around UI automation | Not suitable as the plugin backend |
| MuteDeck companion and local API | Mute, camera, leave, status; other actions are configurable | Yes for core controls | Mature external implementation, REST and WebSocket status APIs | Requires a separately installed and running commercial companion, adds a third-party dependency, blur and hand state are not core status fields | Build-versus-buy alternative only |
| Retired Teams localhost API | Historically all requested controls and reactions | Historically yes | This was the clean official-plugin behavior | Retired, non-published, pairing removed, not available as a supported target | Reject |
| Microsoft Graph calling APIs | Controls a bot's own call | For the bot | Published Microsoft API | Does not control the user's existing desktop call; delegated permissions are not supported for call mute | Reject |
| Teams meeting app or TeamsJS | Meeting context, notifications, app stage features | Meeting metadata only | Supported Teams extension model | Does not expose the requested native client microphone, camera, blur, hand, reaction, or leave controls | Reject |
| DOM injection, coordinate clicks, OCR, or image matching | Potentially all visible controls | Weak | Can automate otherwise inaccessible UI | Unsupported in the signed desktop client, layout and theme fragile, extra privacy permissions, poor localization and display scaling behavior | Reject |

### Why Graph and TeamsJS are not replacements

The Microsoft Graph [call mute endpoint](https://learn.microsoft.com/en-us/graph/api/call-mute?view=graph-rest-1.0) mutes the calling application itself. It uses application permissions, and delegated work or school and personal permissions are explicitly unsupported. A Graph call resource represents a bot or application-created call, not the user's already running Teams desktop call.

The current [Teams meeting apps API list](https://learn.microsoft.com/en-us/microsoftteams/platform/apps-in-teams-meetings/meeting-apps-apis) covers meeting context, participant lookup, notifications, captions, meeting events, and sharing app content to the stage. It does not expose the requested native meeting controls. Building a Teams app would add tenant deployment, authentication, and admin-policy work without solving this problem.

### Why interface control is a credible post-retirement direction

This repository's live test is the strongest evidence for this exact implementation. Current commercial evidence points in the same direction. MuteDeck removed Teams pairing after the API retirement and reports that Teams continues to work through interface control on macOS. Its August 2026 changelog also records real maintenance issues around changed Teams controls, second displays, focus, localization, and compact sharing UI. See [MuteDeck 4.9.3](https://mutedeck.com/changelog/mutedeck-v493).

This confirms both sides of the tradeoff: native interface control remains feasible, but it must be treated as a maintained integration with strong diagnostics and regression tests.

## Recommended control design

### Command contract

Expand the helper from reaction-only commands to explicit desired-state commands:

```text
status
mute
unmute
camera-on
camera-off
blur-on
blur-off
hand-raise
hand-lower
leave
react like|love|applause|laugh|surprise
```

Explicit desired-state commands are safer than blind toggles. They let Stream Deck multi-actions request a known end state, avoid a double press when an event is retried, and become no-ops when Teams is already in the requested state. A separate toggle action can be implemented by reading state first, then issuing one explicit command.

Return one machine-readable JSON object on standard output and retain stable exit codes on standard error. A useful result shape is:

```json
{
  "meetingActive": true,
  "microphone": "muted",
  "camera": "off",
  "backgroundBlur": "unknown",
  "hand": "lowered",
  "command": "mute",
  "changed": false
}
```

Every state field should support `unknown` and `unavailable`. The plugin must not display a confident two-state icon when Teams did not expose enough information to know the state.

### Control-by-control strategy

| Function | Primary Accessibility action | Shortcut fallback on macOS | State confirmation | Risk |
|---|---|---|---|---|
| Mute or unmute | Press the exact meeting microphone control after interpreting whether its accessible action is `Mute` or `Unmute` | `Command+Shift+M` | Re-scan for the opposite action label or a reliable value/description change | Low to medium |
| Camera on or off | Press the exact meeting camera control after interpreting `Turn camera on` or `Turn camera off` | `Command+Shift+O` | Re-scan label/value after the action | Low to medium |
| Raise or lower hand | Press the exact `Raise your hand` or `Lower your hand` meeting control | `Command+Shift+K` | Re-scan for the opposite action label | Low; raise was already observed live |
| Leave call | Press an exact `Leave` meeting button, never `End meeting for all` | `Command+Shift+H` | Confirm the meeting window or meeting controls disappear | Medium; Teams has moved this control in recent releases |
| Enable or disable blur | Open the camera dropdown or effects surface, select the exact `Blur` or `None` option, then apply if Teams requires it | Qualify `Command+Shift+P` against the installed client before enabling it | Read the selected effect if exposed; otherwise report `unknown` after a successful press | Highest |
| Reactions | Keep the existing `React` popover flow and exact semantic reaction selection | None documented for individual reactions | Local action accepted, with end-to-end delivery confirmed by another participant during qualification | Medium |

Microsoft's current [Teams keyboard shortcut page](https://support.microsoft.com/en-us/accessibility/teams/keyboard-shortcuts-for-microsoft-teams) documents the Mac defaults for mute, camera, hand, and leave. The same page now says Teams shortcuts can be customized, so hard-coded defaults cannot be the only path.

The [Microsoft Teams Free shortcut article](https://support.microsoft.com/en-us/teams/free/settings/use-keyboard-shortcuts-in-microsoft-teams-free) currently lists `Command+Shift+P` for background blur, but a separate [personal and small business shortcut article](https://support.microsoft.com/en-us/accessibility/teams/keyboard-shortcuts-for-microsoft-teams-for-personal-and-small-business-use) describes it as opening background settings instead of directly applying blur, and the current work or school shortcut table omits it. Treat blur by shortcut as unqualified until it is tested in the installed client. The Accessibility path should explicitly select `Blur` or `None`. Blur can also be disabled by tenant policy, as documented in [Teams meeting policies for video effects](https://learn.microsoft.com/en-us/microsoftteams/meeting-policies-audio-and-video).

Apple exposes both required primitives: [`AXUIElementPerformAction`](https://developer.apple.com/documentation/applicationservices/axuielement) for semantic control activation and [`CGEvent.postToPid`](https://developer.apple.com/documentation/coregraphics/cgevent) for posting keyboard events to a specific process. Posting to the Teams PID is preferable to activating Teams and sending a global keystroke because it offers a chance to avoid stealing focus. It still needs live validation because Teams decides how to route and handle the event.

### Selecting the safe meeting target

Generalize the existing scorer instead of adding broad text searches:

1. Restrict candidates to `com.microsoft.teams2` processes and meeting-like windows.
2. Require a pressable role and `AXPress` or an explicitly allowed alternative action.
3. Prefer stable accessibility identifiers when they are present.
4. Prefer exact action text over substring matches.
5. Prefer the active or focused meeting window, but support the compact sharing toolbar.
6. Reject chat, message, settings, pre-join, device-preview, and notification controls.
7. For leave, explicitly reject `End meeting`, `End meeting for all`, decline-call, and dismiss controls.
8. If two candidates remain plausibly equal, fail safely and emit diagnostics instead of pressing either.

Use separate scorers and fixtures for microphone, camera, hand, leave, effects launcher, blur, and no-effect. Do not build one generic `BestButtonNamed` function that can cross control contexts. The existing reaction regression shows why context-specific negative evidence matters.

### Toolbar visibility and fallback behavior

The current reaction instructions require visible meeting controls. Broader controls should not rely on the user moving the pointer first.

Recommended sequence:

1. Scan the known meeting window and compact sharing window.
2. If the exact control is present, press it through Accessibility.
3. If it is absent, request that relevant Accessibility elements be scrolled into view where supported, then re-scan briefly.
4. If the control is still absent and a qualified shortcut exists, post the shortcut to the selected Teams PID.
5. Re-scan to confirm the state changed. Report failure if the result cannot be confirmed for a requested explicit state.
6. For a nested control with no qualified shortcut, currently blur, raise the Teams window only as a documented last resort. `AXRaise` can change the foreground window, so it should not be presented as an invisible operation.

Do not move or click the user's mouse. A vendor implementation may need that technique, but this project already has a cleaner `AXPress` path and should preserve it unless live evidence proves a specific control cannot be invoked otherwise.

## Stream Deck state and process lifecycle

### First milestone: one-shot helper

Keep the current short-lived helper for the first implementation:

- A key press launches one allow-listed command through `execFile`.
- The helper reads the current state, performs at most one requested change, verifies the result, emits JSON, and exits.
- The existing shared execution lock prevents overlapping actions.
- Actions use `DisableAutomaticStates: true`.
- The Node plugin calls `setState` only after a confirmed result and calls `showAlert` on `unknown`, ambiguity, timeout, or failure.
- The plugin refreshes state when an action appears and after every command.

Elgato's [multi-state key documentation](https://docs.elgato.com/streamdeck/sdk/guides/keys/) supports two visual states and plugin-controlled `setState`. Since the SDK only has two well-supported states, show `unknown` or `unavailable` with a temporary title or generated image rather than mapping it to on or off.

This milestone will not stay synchronized when a user changes Teams directly. It should be described honestly as confirmed-after-action state, not real-time state.

### Later milestone: live state observer

If live button state is required, evolve the helper into a child process owned by the Stream Deck plugin:

```text
Stream Deck Node plugin
    <-> newline-delimited JSON over stdin/stdout
    <-> native helper with cached meeting window and AXObserver
    <-> Teams accessibility notifications
```

`AXObserver` can receive notifications from a target application. Use it to invalidate cached controls and trigger a bounded state reconciliation scan. Electron/WebView accessibility notifications may be incomplete, so use a low-frequency poll only while relevant Stream Deck actions are visible as a fallback. The helper must exit when its parent plugin exits, so this remains a bundled child process rather than a daemon or login item.

Avoid continuously repeating the current 30,000-element full traversal. Cache the meeting window, scan only relevant subtrees after discovery, and rate-limit refreshes. Recent vendor notes show that aggressive meeting detection can create responsiveness and CPU problems, so performance needs its own qualification.

## Reaction alternatives

The current Accessibility implementation remains the best standalone option for reactions in the Teams desktop client.

Alternatives considered:

- Keyboard shortcuts: viable for common call toggles, but Microsoft documents no shortcut for selecting Like, Love, Applause, Laugh, or Surprise.
- Teams localhost API: formerly ideal, now retired and unsupported.
- Microsoft Graph or TeamsJS: no endpoint for sending a live reaction as the signed-in desktop participant.
- Teams web browser extension: technically viable for Teams web by clicking semantic DOM controls, but it would not control the installed desktop app and would add browser permissions and packaging.
- MuteDeck: viable if accepting a separate paid companion. Its local [REST and WebSocket API](https://mutedeck.com/help/api/) provides core control and status, but this changes the product from a self-contained plugin to an integration with another running application.
- Coordinate, image, or OCR automation: inferior to the current semantic Accessibility path and should not be added.

Therefore, reactions should continue to use the current `React` launcher plus popover selection. The recommended fallback work applies to the five new call controls, not to individual reactions.

## Reaction bursts and long press

### Short answer

Yes, long-press-to-repeat can be implemented with the current macOS Accessibility direction, but not by simply calling the current helper in a tight Node.js loop.

The Stream Deck SDK emits a key-down event when a key is pressed and a separate key-up event when it is released. The official [Stream Deck plugin event reference](https://docs.elgato.com/streamdeck/sdk/references/websocket/plugin/) documents both events and gives each action instance its own context identifier. That is enough to start a repeat session on `onKeyDown` and cancel the matching session on `onKeyUp`.

A target of two to four accepted reaction actions per second appears technically plausible after optimization, but it is not yet demonstrated in a live Teams meeting. Ten delivered reactions per second cannot be promised. The former official plugin sent a direct local API command, while the Accessibility path must interact with Teams' reaction picker and may have to wait for it to close and reopen for every reaction.

Microsoft's current [live reactions documentation](https://support.microsoft.com/en-us/teams/meetings/express-yourself-in-microsoft-teams-meetings-with-live-reactions) explains how reactions appear and that organizers can disable them, but it publishes no live-meeting repeat rate, cooldown, or delivery guarantee. Teams may accept, coalesce, delay, or discard rapid local UI actions. Accessibility success proves only that Teams accepted the local action request, not that every heart was delivered to other participants.

### Why the current code cannot create a fast burst

The current TypeScript action implements only `onKeyDown`. One physical hold therefore starts one reaction, not repeated reactions. `ReactionCoordinator` has one global `running` flag and returns `busy` for every additional attempt until the current helper process exits.

Each helper invocation then performs this sequence:

1. Start a new native process.
2. Traverse the Teams Accessibility trees with `ScanTeams()`.
3. Press the meeting `React` launcher.
4. Wait at least 120 ms before scanning for the popover.
5. Traverse the Teams Accessibility trees again, possibly several times.
6. Press the requested reaction.
7. Wait another 350 ms before exiting.

The two deliberate waits alone total 470 ms. Even if process startup, tree traversal, Teams rendering, and Accessibility calls took zero time, the ceiling would be approximately `1 / 0.47 = 2.13` reactions per second. The real rate is lower. The six-second Node timeout also makes one hung iteration a poor building block for a hold loop.

Rapid manual presses do not queue work today. They produce a `busy` result and an alert while the first reaction continues.

### Minimal experiment

A small TypeScript-only experiment could prove the Stream Deck hold interaction:

- `onKeyDown` sends one reaction immediately and starts a sequential loop.
- `onKeyUp` marks that action context as released.
- The loop awaits each existing one-shot helper before starting the next.
- Releasing the key stops scheduling new helpers, while the current helper is allowed to finish.

This is useful only as an interaction proof. It preserves the 470 ms delay, repeats full-tree scans, starts a process for every reaction, and is unlikely to sustain two reactions per second reliably. It should not become the final implementation.

### Recommended burst architecture

Start one native helper process for the complete hold:

```text
keyDown
    -> spawn teams-reaction burst love
    -> helper discovers and caches meeting controls once
    -> helper repeats bounded AXPress cycles

keyUp
    -> close helper stdin or send stop\n
    -> helper finishes at most one in-flight action
    -> helper reports aggregate result and exits
```

The Node plugin should return from `onKeyDown` after starting the session so it remains ready to receive `onKeyUp`. It should identify the hold by the Stream Deck action context. Only one global reaction session should run at a time, matching the current protection against overlapping reaction popovers.

The native helper should optimize in this order:

1. Discover the Teams meeting process, meeting window, and exact `React` launcher once.
2. Open the reaction picker and acquire the exact requested reaction element.
3. First test whether repeated `AXPress` calls on that same element remain valid while the picker is open. If Teams accepts several presses before invalidating or closing the popover, this is the only credible path toward the historical 10-per-second effect.
4. If the reaction element becomes invalid after one press, cache the launcher, reopen the picker, and reacquire only the small popover subtree for each iteration.
5. Use `AXObserver` notifications or a short targeted poll to detect picker appearance and disappearance. Do not repeat the current full application traversal on every iteration.
6. Rediscover the meeting window and launcher only when a cached element returns an invalid-element error or Teams changes windows.
7. Stop immediately when the meeting ends, reactions become unavailable, the requested control is ambiguous, or Accessibility returns a terminal error.

The first live proof should answer one decisive question: does Teams keep the reaction button valid long enough for repeated `AXPress` actions, or does every reaction require a complete close-and-reopen cycle? The achievable rate depends primarily on that behavior.

### Rate and safety policy

"As fast as possible" should not mean an unbounded loop. A lost key-up event, device disconnect, profile change, or stalled Teams UI must not create an endless reaction process.

Recommended initial policy:

- Send one reaction immediately on key-down.
- Start repeating only after a hold threshold of about 300 ms, preserving normal single-tap behavior.
- Default to 3 attempts per second during the hold.
- Stop scheduling immediately on key-up.
- Stop after 3 seconds by default, matching the intended wave effect.
- Enforce hard internal guards of 10 attempts per second and 30 attempts per hold, even if later live testing enables a faster user setting.
- Stop on `onWillDisappear`, device disconnect, plugin shutdown, meeting end, or the first repeated control-selection failure.
- Do not enable repeating when the action runs inside a Stream Deck multi-action. Treat that invocation as a single reaction because no physical hold duration is available.

The 3-per-second default is a test starting point, not a claimed delivery rate. Increase it only after second-participant validation shows that Teams renders the additional reactions and remains responsive.

### Feedback and diagnostics

Do not flash `showOk` for every heart. It would add noise and extra Stream Deck traffic. Show success once when the hold ends if at least one reaction was accepted. Show an alert when none were accepted or the burst stopped on an error.

Return one aggregate result:

```json
{
  "reaction": "love",
  "attempted": 10,
  "accessibilityAccepted": 9,
  "elapsedMs": 3100,
  "stopReason": "key-up"
}
```

Log aggregate counts and timing only. Keep meeting titles, participant names, and Accessibility tree text out of normal logs.

### Required live qualification

Test burst rates of 1, 2, 3, 5, and 10 attempts per second for three seconds. Record three separate measurements:

1. Attempts scheduled by the helper.
2. Calls for which `AXUIElementPerformAction` returned success.
3. Hearts observed by a second meeting participant or device.

The third measurement is the real result. A green Accessibility return is insufficient if Teams coalesces or drops reactions.

Also verify:

- Single tap still sends exactly one reaction.
- Holding past the threshold begins repeating without a second physical press.
- Release stops within one in-flight iteration.
- A missing key-up event is contained by the duration and count guards.
- The reaction picker may close after every selection without leaving orphaned popovers.
- Another reaction key cannot start a competing burst.
- Teams remains responsive and helper CPU stays bounded.
- Reactions disabled by organizer or policy stop the burst with one clear alert.
- Meeting end, minimized Teams, compact sharing toolbar, and second-display cases terminate safely.

### Burst conclusion

Long-press reaction waves fit the current Accessibility architecture, but they require a dedicated burst mode in both the Node plugin and native helper. A repeated one-shot loop is too slow and wasteful. The optimized target should begin at three attempts per second, then be tuned from live delivery evidence. Reaching 10 reactions per second depends on whether Teams accepts repeated presses on one live reaction element; that remains the critical unverified experiment.

## Implementation sequence

1. Add `inspect-controls` before adding any action. Capture sanitized accessibility output in a live meeting for microphone on/off, camera on/off, hand raised/lowered, blur on/off, normal toolbar, compact sharing toolbar, and organizer versus attendee leave controls.
2. Save each sanitized tree as a deterministic test fixture before writing selection logic.
3. Refactor process and tree discovery out of reaction-specific code without changing the proven reaction scorer.
4. Implement `status`, `mute`, `unmute`, `camera-on`, `camera-off`, `hand-raise`, and `hand-lower` with direct `AXPress` and post-action verification.
5. Add `leave` with exact negative matching and an optional hold-to-leave Stream Deck setting.
6. Implement blur through the visible effects UI. Return `unavailable` when policy or client capability removes it, and `unknown` when selection state cannot be read.
7. Build a small `CGEvent.postToPid` proof of concept for mute, camera, hand, leave, and blur. Test it while another application has focus, while Teams chat has focus, while Teams is minimized, and while PowerPoint Live or Whiteboard is on stage.
8. Enable only the shortcuts that pass those tests, and keep them as fallbacks behind control-specific feature flags.
9. Add two-state Stream Deck actions with automatic state changes disabled. Update state only from helper results.
10. Qualify real-time observation separately. Do not make a persistent helper a prerequisite for basic one-press controls.

## Required live validation

No implementation should be described as production-ready until these cases pass in actual Teams meetings:

- Microphone toggled from Stream Deck, Teams UI, a headset button, and another control surface.
- Camera toggled from Stream Deck and Teams UI.
- Raise and lower hand in both directions.
- Leave as attendee and organizer, with proof that `End meeting for all` is never selected.
- Blur enabled from no effect and disabled from blur.
- Blur when camera is off and when the tenant policy disables video effects.
- Teams toolbar visible, auto-hidden, minimized, and on a second display.
- Compact toolbar while sharing.
- Teams chat focused and PowerPoint Live or Whiteboard active.
- Multiple Teams windows and guest meetings hosted by another organization.
- English plus each supported localized Teams interface.
- Accessibility permission granted to the actual packaged helper or Stream Deck parent after install and upgrade.
- Rapid repeated key presses and helper timeout recovery.
- Current installed Teams plus at least one later Teams update.

## Final decision

Build on the current Accessibility helper, not around it.

The smallest reliable next milestone is direct semantic control for mute, camera, hand, and leave, followed by the more complex blur flow. Add targeted keyboard events as a tested fallback, especially for controls that disappear with toolbar changes. Keep reactions on the existing popover path.

This approach preserves the project's self-contained installation, needs no Microsoft account token or tenant app, can provide verified state, and has a proven local foundation. Its cost is ongoing compatibility work when Teams changes its Accessibility tree, so fixtures, safe ambiguity failures, privacy-safe diagnostics, and live qualification are part of the implementation rather than optional cleanup.
