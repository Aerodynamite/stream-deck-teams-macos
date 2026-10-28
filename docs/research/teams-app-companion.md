# Research: a Teams app companion for Stream Deck

Date: 2026-10-28

## Answer and recommendation

We can build a Teams app and distribute it through the Teams Store, subject to
Microsoft's certification and tenant policies. However, the documented app APIs
do not provide the control surface this plugin needs for the signed-in user's
existing Teams desktop meeting. Installing our app inside Teams would not give
it privileged access to the native meeting toolbar. Teams tabs are web pages in
sandboxed iframes, and Microsoft explicitly says they cannot use native plugins.
See [Teams tabs](https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/what-are-tabs)
and [Store publication](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/deploy-and-publish/appsource/publish).

**Recommendation:** retain the bundled macOS Accessibility helper for existing
meeting controls. Do not build or publish a Teams companion solely to remove
Accessibility permissions or make those controls more reliable. A companion is
worth considering if we add separate features such as meeting-aware workflows,
app-owned polls or collaboration, or a configuration surface inside Teams.
This recommendation is an engineering inference from the supported interfaces
described below, rather than a claim that Microsoft could never add such an API.

## Scope and evidence

The target is the current user's microphone, camera, hand, reactions, and local
Leave action in their already running macOS Teams desktop call. Controlling a
bot, a custom calling client, or an app's own UI is a different requirement.

This research checked current official Microsoft documentation and API references,
plus Elgato's first-party notice about its own integration. Repository context
was checked against the current checkout on `main`: the
[README](../../README.md), [architecture](../architecture.md),
[call-controls research](teams-call-controls.md), and current TypeScript command
coordination. The older [plugin handoff](PLUGIN_HANDOFF.md) is historical context,
not proof of today's runtime behavior. No plugin code changed, and no Teams app,
bot, cloud relay, or live meeting experiment was implemented for this research.

## What a Teams app actually receives

A meeting app can obtain context, access documented meeting metadata, send
notifications, participate in meeting lifecycle workflows, and share its own
content to the stage. These are extension points for the app's experience, not
general access to Teams internals. The published
[meeting app API inventory](https://learn.microsoft.com/en-us/microsoftteams/platform/apps-in-teams-meetings/meeting-apps-apis)
describes those capabilities and their permissions.

A tab runs an HTTPS-hosted web page and calls TeamsJS to communicate with its
host. Installing the manifest does not load our Objective-C helper into Teams
or install a native background service. The hosting and origin requirements are
documented in [tab prerequisites](https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/how-to/tab-requirements).
Consequently, a companion can expose an API we design for its own features, but
cannot create a Teams microphone API that its host does not expose.

### The important audio distinction

TeamsJS exposes `getIncomingClientAudioState` and `toggleIncomingClientAudio`.
These read or change the user's **incoming speaker audio**, meaning what the
user hears. They do not mute or unmute the user's outgoing microphone. The latest
`meeting` module's overview mentions microphone state, but the actual function
contracts explicitly describe incoming speaker audio. The reviewed public
function list does not contain outgoing microphone mute/unmute, camera, hand,
reaction, or local-leave methods such as `requestMuteAudio` or
`requestUnmuteAudio`. See the
[current TeamsJS meeting reference](https://learn.microsoft.com/en-us/javascript/api/@microsoft/teams-js/meeting?view=msteams-client-js-latest).

## Capability matrix

Here, "no documented route" means no supported control for the existing desktop
endpoint was found in the reviewed public APIs. It does not mean that unrelated
SDKs lack similarly named methods.

| Stream Deck action or need | Teams app / TeamsJS | Graph or another endpoint | Consequence for this plugin |
|---|---|---|---|
| Mute and unmute outgoing microphone | No documented route | Graph can mute the application itself, or server-mute a participant in a bot-controlled group call | Keep Accessibility for the desktop microphone |
| Camera on and off | No documented route | A custom calling client can control its own media | Keep Accessibility for the desktop camera |
| Raise and lower own hand | No documented route | A separate calling endpoint is a different client | Keep Accessibility |
| Send native meeting reactions | No documented route | An app-owned animation or message is not a native Teams meeting reaction | Keep Accessibility and qualify delivery separately |
| Leave only this user's desktop call | No documented route | Graph hang-up deletes the application's own call leg | Keep precise local Leave selection |
| Background blur | No documented route | Effects in a custom client would belong to that client | Does not make the existing experimental helper path an app API |
| Mute incoming speakers | Documented get and toggle APIs | Different from outgoing microphone mute | Possible new feature, subject to client qualification |
| Meeting context, lifecycle, app content | Documented app capabilities | Additional bot or Graph permissions may be needed | Useful only for a broader product scope |
| Native mic/camera/hand state on the deck | No documented complete desktop-state feed | Bot roster or custom-client state has different semantics | Preserve unknown and unavailable states |

Sources for the distinction between app functions and client controls:
[TeamsJS meeting API](https://learn.microsoft.com/en-us/javascript/api/@microsoft/teams-js/meeting?view=msteams-client-js-latest),
[meeting apps](https://learn.microsoft.com/en-us/microsoftteams/platform/apps-in-teams-meetings/meeting-apps-apis),
[Graph self-mute](https://learn.microsoft.com/en-us/graph/api/call-mute?view=graph-rest-1.0),
[Graph participant mute](https://learn.microsoft.com/en-us/graph/api/participant-mute?view=graph-rest-1.0),
[Graph hang-up](https://learn.microsoft.com/en-us/graph/api/call-delete?view=graph-rest-1.0),
and [custom Teams calling endpoints](https://learn.microsoft.com/en-us/azure/communication-services/concepts/teams-endpoint).

## Why Graph is not a remote control for the desktop user

`POST /communications/calls/{id}/mute` explicitly mutes the application itself.
It supports application permissions, not delegated user permissions. It cannot
be turned into "mute my existing desktop microphone" by signing the user in.
See [Graph call mute](https://learn.microsoft.com/en-us/graph/api/call-mute?view=graph-rest-1.0).

Graph also has participant mute. This server-drops the selected participant's
audio in a group call and requires application calling permissions. It is a real
moderation capability, so saying "Graph can only ever mute the bot" would be
inaccurate. It is nevertheless not the desktop user's bidirectional mic control
or a replacement for that client's microphone-state feed. See
[participant mute](https://learn.microsoft.com/en-us/graph/api/participant-mute?view=graph-rest-1.0).

Likewise, Graph hang-up removes the application's call leg while the group call
continues. It does not select the user's existing desktop session. Using
participant removal as a substitute would change the semantics of our local
Leave action. See [delete call](https://learn.microsoft.com/en-us/graph/api/call-delete?view=graph-rest-1.0).

## The former local device API is a separate, retired integration

There used to be an external-device bridge, commonly described as the Teams
localhost or WebSocket API. Its pairing model was separate from installing a
Teams meeting app. Microsoft's support article still describes a desktop
`Settings > Privacy > Manage API` setting, an administrator-controlled policy,
token generation, and explicit Allow or Block pairing. It lists essentially our
desired controls. See
[Microsoft's device pairing instructions](https://support.microsoft.com/en-us/teams/calls-devices/connect-to-third-party-devices-in-microsoft-teams).

That page is not sufficient evidence of present availability. Elgato's June 25,
2026 notice says Microsoft discontinued the required API, took it offline, and
that existing Stream Deck Teams actions no longer function. It dates Marketplace
removal to December 12, 2025. The same Elgato page retains obsolete setup steps
below the notice, so those steps must not be read as a current workaround. See
[Elgato's retirement notice](https://help.elgato.com/hc/en-us/articles/26249796361613-How-to-pair-Stream-Deck-plugin-with-Microsoft-Teams).

The earlier repository research records tenant Message Center notice MC1266901
and a June 30, 2026 final retirement date. That notice is not independently
verified here through an authenticated Microsoft tenant, so the date is not
needed for this recommendation. The first-party vendor notice already rules
out treating the former bridge as a supported new backend. No current public
Microsoft WebSocket protocol or replacement macOS device API was identified.
Current macOS pairing availability was not tested. Building a Store app does
not restore this retired external integration.

## Could Azure Communication Services solve it?

Azure Communication Services supports custom applications that join Teams
meetings, including applications using a Teams identity. Those applications
own a separate calling endpoint and can provide their own media controls.
This could support a different product where the user joins through our client;
it does not document attachment to and control of the existing Teams desktop
endpoint. Teams-identity calling also adds authentication, Azure services,
consumption charges, and feature qualification. See
[Teams meeting interoperability](https://learn.microsoft.com/en-us/azure/communication-services/concepts/join-teams-meeting)
and [communication as a Teams user](https://learn.microsoft.com/en-us/azure/communication-services/concepts/teams-endpoint).

This alternative also needs lifecycle review. Microsoft's September 2026
announcement retires standalone ACS offerings on September 30, 2028 and subjects
the Calling SDK to breaking changes. Supported Teams-aligned scenarios, including
Teams Meeting Interoperability, continue under the documented migration model.
It would be inaccurate to say all ACS calling is simply disappearing. See the
[ACS retirement and breaking-changes guide](https://learn.microsoft.com/en-us/azure/communication-services/acs-retirement-and-breaking-changes-guide).

## Distribution and connection design

Store distribution is possible in principle. It requires Partner Center
submission, certification, test access, and a complete working experience.
Microsoft validates across desktop, web, and mobile clients. A macOS and Stream
Deck dependency would need clear disclosure and review; approval of our proposed
companion is unverified. See
[publishing](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/deploy-and-publish/appsource/publish)
and [Store validation guidelines](https://learn.microsoft.com/en-us/microsoftteams/platform/publishing/office-store-approval).

Store publication does not override tenant restrictions. Administrators can block
apps or restrict their availability. A prototype can instead use policy-permitted
custom upload or an organization catalog before public submission. See
[app management](https://learn.microsoft.com/en-gb/microsoftteams/admin-settings)
and [custom app distribution](https://learn.microsoft.com/en-us/microsoftteams/teams-custom-app-policies-and-settings).

If broader app-owned features justify a companion, a possible design is an
HTTPS-hosted Teams tab and Stream Deck plugin paired through an authenticated
relay. This is an architectural proposal, not a Microsoft meeting-control API.
A direct localhost connection would need separate testing of TLS, browser and
Teams security restrictions, allowed origins, and app lifetime. Neither design
adds native meeting permissions. Do not assume installing a tab gives it a
permanent background execution guarantee.

Any future bridge should retain explicit desired-state commands, the allow-list,
one operation lock, bounded reaction sessions and release cancellation, and
unknown/unavailable state handling. Pairing must bind commands to the intended
user, device, and meeting without logging meeting titles or participant names.
Leave must retain local-participant semantics. These are existing project
constraints, not additional capabilities supplied by Teams.

## Decision and remaining verification

1. Continue the current Accessibility backend and its live qualification work.
2. Revisit a companion when there is an app-owned feature with independent value,
   or Microsoft publishes an explicit supported desktop control API.
3. Before a control-backend prototype, require a documented API for the exact
   outgoing mic, camera, hand, reaction, or local Leave operation. Metadata and
   incoming speaker audio do not pass that gate.
4. If incoming speaker control or meeting-aware workflows are wanted, test a
   small private app first. Verify current macOS support, meeting and call types,
   tenant policies, app closure/background behavior, and multiple meetings.

This document establishes API feasibility from published sources. No live cases
were verified here. Existing live gaps, including safe Leave in a disposable
meeting and reaction delivery observed by another participant, remain tracked in
the [control testing checklist](../testing/teams-call-controls.md).
