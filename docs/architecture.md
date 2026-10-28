# Architecture

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

Stream Deck owns a bundled native child process while meeting-control keys are visible. Hand, Leave, and reaction operations use separate bounded one-shot invocations.

## Control state behavior

Mute, camera, and hand actions use two Stream Deck states with automatic state changes disabled. The plugin asks the helper for current state when an action appears and updates all visible control keys after every completed command.

Accessibility attributes are read in batches and label definitions are shared within each helper process. Mute and camera changes verify fresh attributes on the discovered state controls immediately, then poll every 20 ms while awaiting confirmation. If Teams replaces the target, the helper performs a full scan without pressing it a second time. This avoids a second full tree traversal and a fixed 120 ms wait on the normal path while preserving state confirmation and the operation lock. Reactions also check for the picker immediately rather than waiting before their first scan.

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

The persistent helper observes Accessibility and workspace notifications. It debounces reconciliation to at most four times per second and refreshes known controls every two seconds as a fallback while visible keys retain the helper. Notification support varies by Teams version, so direct Teams changes can take up to the fallback interval plus reconciliation time to appear on the deck.

Warm requests compare process/window identities and read fresh control attributes before acting. Changed context, invalid references, structural notifications, wake, and one-shot operations invalidate discovery. Foreground requests rediscover unavailable controls; idle reconciliation does not repeatedly traverse an empty meeting tree. Leave always uses fresh discovery. Hand, Leave, and reactions pause idle observation and invalidate the cache before it resumes.

The Node client permits one request at a time under the existing operation lock. Timeouts, malformed output, and crashes fail the current request without replaying a potentially completed press. It waits for the old child to close before starting another, with a kill watchdog for unresponsive children. Closing stdin or losing the parent stops native serving. The helper closes when the last control disappears; commands without visible keys have a 500 ms reuse window for Multi Actions.

The SDK has no public disconnect callback. A read-only Stream Deck global-settings heartbeat every five seconds, with a three-second deadline, stops the plugin and its children after a lost connection. Device disconnects release that device's visible controls; process shutdown and reaction release/disconnect handling remain bounded. No daemon or login item is installed.

## Teams toolbar compatibility

Accessibility traversal and popup discovery compare full element identities, so hash collisions cannot hide a toolbar or mistake a new popup control for an old one. Traversal still bounds depth and element count and stops cycles.

Reaction launcher selection requires a matching action label and rejects menu items and chat controls. Recent-item titles containing reaction words must not count as meeting controls or mark a meeting active.

The helper reads Chromium's `AXCustomContent` descriptions as well as visible labels, and falls back to `AXDOMIdentifier` when `AXIdentifier` is absent. Teams can keep a short label such as `Raise` unchanged while its custom description switches between `Raise your hand` and `Lower your hand`.

The React control can expose hand state directly in its custom description. When a hand change needs the control inside React, the helper opens the picker and dismisses it afterward with Escape sent only to Teams. Cleanup checks a cached picker control and retries at most three times if Teams ignores dismissal, without a full-tree scan or focus changes. Reactions open React directly without scrolling first, since scrolling immediately before pressing can invalidate the new toolbar's action path. Hand changes have a 15-second helper timeout to allow the picker and state verification round trip. Meeting-control shortcut fallbacks remain disabled by default.

## Persistent protocol

The internal `serve` mode accepts bounded newline-delimited JSON for `status`, `mute`, `unmute`, `camera-on`, and `camera-off`. Requests have positive integer IDs, a generation token, and an optional boolean `forceFresh`. Responses correlate the ID and generation and contain an exit code and the ordinary state result. Idle state events contain only the state result and generation. `pause` and `resume` frames suspend observation around one-shot operations; generations discard stale events. This protocol does not accept shell commands, arbitrary paths, reactions, hand changes, or Leave.

## Reaction sessions

- A normal tap sends exactly one reaction.
- Holding longer than about 300 ms starts repeating at 7 attempts per second, reusing the open picker and cached reaction control.
- Releasing the key closes the helper's standard input and stops scheduling new attempts.
- A session stops after 5 seconds even if key-up is lost. This budget includes picker setup, so slow setup reduces the total number of reactions.
- Native hard limits cap the rate at 10 attempts per second and the session at 50 attempts.
- Only one Teams operation can run at a time.
- Reactions inside a Stream Deck Multi Action always send once because there is no physical hold duration.

Success feedback is shown once when the session ends. Logs contain only aggregate reaction type, attempt count, Accessibility acceptance count, elapsed time, and stop reason.

See [Development](development.md) for helper commands and experimental shortcut fallbacks. Live measurements and qualification limits are recorded in the [testing checklist](testing/teams-call-controls.md).
