# Publication preparation plan

Last updated: 2026-10-04.

Status: interview paused at the publisher's request. Answers through Q16 are recorded below. Q17 through Q26 remain unanswered; their recommendations are not accepted decisions. Publication implementation has not started.

This plan records the publisher's decisions following the [publication readiness review](elgato-marketplace-publication.md). Technical findings and external requirements remain in that review; live qualification results belong in the [test checklist](../testing/teams-call-controls.md).

## Resume here

Continue with the [remaining questions, Q17 through Q26](publication-questions.md). The publisher requested all follow-up questions together, rather than one per message. Preserve the answers below and do not reopen them unless new evidence creates a conflict.

After the remaining answers are recorded, confirm the complete implementation scope with the publisher. Final product naming and paid signing are deliberately deferred; the final license text and contributor permissions are still unresolved. None of these notes establishes that the plugin is ready for public release.

## Agreed finish line

The agent prepares the release package, Marketplace listing images and copy, support documentation, and qualification evidence. The publisher handles Marketplace submission and public release.

Any remaining steps requiring publisher accounts, permissions, hardware, or live meeting participation must be identified in the handoff. Preparation does not establish release readiness while required qualification remains incomplete.

## Agreed distribution model

The first Marketplace release will be free. This decision does not settle source-code licensing or support commitments.

## Licensing intent

The licensing policy and its rationale are recorded in [ADR 0001](../adr/0001-workplace-use-and-paid-redistribution.md). That ADR records intent, not an applied license.

The publisher explicitly permits people and companies to use the plugin for work. Workplace use must not require a paid license.

The publisher wants terms that allow use, modification, and free sharing while restricting sale of the plugin itself and paid derivatives. MIT has not been accepted, and no replacement license has been selected. A blanket restriction on commercial use does not express the agreed permission for workplace use.

The publisher permits consultants and other service providers to charge for installation, configuration, and support, provided the plugin itself remains free. The intended restriction concerns sale of the software, not payment for these services.

Including a copy of the plugin in a paid bundle requires Heartbit's permission. Paid Stream Deck profiles may link users to the official free download without bundling a copy of the plugin. This distinction was confirmed by the publisher on 2026-09-29.

Selling a modified version also requires Heartbit's permission. People may modify the plugin and share their versions for free. This boundary was confirmed by the publisher on 2026-09-30.

Select or prepare license text that implements these agreed boundaries. Keep the rights and notices for third-party dependencies separate from the terms selected for the project's own code. These recorded permissions express licensing intent; they do not apply a license to the repository.

## Maker Console starting point reported by the publisher

The publisher confirmed that no Maker organization has been created and this plugin has not been uploaded to Maker Console. This is the first publication, with no existing Marketplace product or published identity to preserve.

The publisher will create the organization and handle submission. The product name and final identifiers remain to be settled. Existing local development profiles may still reference the current identifiers.

## Agreed publisher identity

Use **Heartbit** as the public publisher name, with that exact spelling and capitalization. Prepare the manifest author and listing materials to match the Heartbit Maker organization the publisher will create.

This is a public branding decision, not a statement about legal entity status, domain ownership, or Apple Developer account identity. Those details must not be inferred from the name.

## Provisional product name

Use **Meeting Deck** as the working title. The publisher accepted it provisionally and wants to brainstorm the final name later. Name availability and rights have not been established.

Keep final naming as an explicit pre-submission decision. Do not rename plugin or action identifiers based on this provisional title. Prepare listing copy and artwork so the final title can be substituted later.

## Agreed preparation budget and deferred signing

Keep preparation at zero additional monetary cost for now. The publisher does not have an Apple Developer Program membership and has chosen to defer paid enrollment. Do not incur fees for memberships, services, hosting, or assets without a later explicit budget decision.

Developer ID signing and notarization are the recommended macOS distribution approach, not an established requirement specific to this helper in the reviewed Elgato guidelines. Apple requires program membership to issue Developer ID certificates; notarization checks Developer ID-signed software and produces a ticket for Gatekeeper. See [Apple's Developer ID guidance](https://developer.apple.com/developer-id/).

Apple lists membership at USD 99 per year, with regional pricing shown during enrollment, as checked on 2026-09-24. See [Apple enrollment](https://developer.apple.com/programs/enroll/). Local development and package preparation have already succeeded without membership.

Prepare the plugin and release workflow using existing tools. Keep production signing and notarization as a deferred release decision rather than a prerequisite for preparation. Establish Marketplace expectations and test the actual processed package on a clean Mac before claiming the existing ad-hoc-signed helper is suitable for public distribution. Do not treat the absence of an explicit signing requirement in the [Elgato distribution guide](https://docs.elgato.com/streamdeck/sdk/introduction/distribution/) as proof of acceptance or trouble-free installation.

If qualification or Marketplace review establishes that paid signing is necessary, report the evidence and leave that release step pending the publisher's decision. A zero-cost preparation budget does not waive qualification or authorize bypassing macOS security controls.

## Agreed reaction behavior

Holding a reaction key must repeatedly send that reaction in the first release. Reaction repeats are part of the release scope, not deferred work.

Retain the existing safety constraints: a bounded session, cancellation on key release, and the single-operation lock. The publisher accepted the current first-release defaults: a roughly 300 ms hold threshold, three attempts per second, and a three-second maximum session. Release stops repetition earlier; holding longer does not extend the session beyond three seconds. Timing can be refined in later releases.

Live qualification must verify cancellation and delivery to a second participant. Accessibility acceptance counts must not be described as confirmed delivery counts.

## Agreed Mac architecture support

The first release will support Apple silicon Macs only. State this requirement clearly in the Marketplace listing, setup guide, and support documentation. Intel support is deferred.

Confirm that Marketplace accepts the disclosed architecture limitation before submission. If it does not, revisit this decision with the publisher rather than silently expanding support. The minimum supported macOS version and its qualification remain to be settled.

## Agreed Teams interface language support

The first release will support the English Teams interface only. Other interface languages are outside the supported scope even if some existing localized labels happen to work. English behavior still requires live qualification.

Include a prominent disclaimer in the Marketplace listing, setup guide, and support documentation, alongside the Apple silicon requirement:

> Requires an Apple silicon Mac and the Microsoft Teams desktop app with its interface language set to English. Other Teams interface languages are not supported in this release. This restriction does not apply to the language spoken in meetings.

## Agreed automatic state updates

The first release must automatically update the Stream Deck microphone, camera, and raised-hand indicators when their state changes directly in Teams. Users must not need to press another plugin key or reload the profile to reconcile those indicators.

The current refresh-on-appearance and refresh-after-command behavior is insufficient for this requirement. Choose the observation mechanism during implementation, preserving the command allow-list, single-operation lock, and bounded reaction sessions. Unknown and unavailable state must remain distinct from confirmed on or off.

Live qualification must cover state changes made directly in Teams and transitions into and out of meetings. The update latency target and behavior when state can no longer be observed remain part of the acceptance criteria to settle.

## Open decisions and deferred work

- Q17 and Q18: support expectations, documentation location, and public contact for private reports and permission requests.
- Q19 and Q20: copyright holder, contributor permissions, artwork provenance, and Heartbit visual branding.
- Q21 through Q24: supported macOS versions, live test arrangements, required meeting situations, and state-update acceptance criteria.
- Q25 and Q26: final feature boundary, Leave behavior, implementation handoff, and deadline.
- Final product name and identifiers: Meeting Deck remains provisional and naming will be revisited later.
- Exact license: select or draft terms implementing the agreed permissions, while preserving third-party licenses. Contributor permission remains unresolved.
- Signing and notarization: paid enrollment is deferred; establish requirements and installed-package behavior without assuming approval or incurring costs.
- Release engineering: choose implementation details within the eventual agreed scope. No signing, runtime-staging, or observation design has been approved by this interview.

Record further answers here as they are agreed. Keep actual test results in the qualification checklist. Missing results, suggested defaults, and unanswered questions must not be represented as completed work or publisher decisions.
