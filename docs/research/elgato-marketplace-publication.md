# Publishing Teams Meeting Controls on Elgato Marketplace

Research date: 2026-09-02

## Scope

This document applies to the plugin in this checkout, currently named **Teams Meeting Controls**, on branch `feature/teams-call-controls`. It covers the current nine-action macOS plugin rather than the earlier reactions-only build.

The conclusions combine:

- the current manifest, package, native helper, tests, and documentation in this repository;
- the Elgato Marketplace and Stream Deck SDK documentation available on 2026-09-02;
- Apple's current guidance for distributing macOS executables outside the Mac App Store; and
- Microsoft's current trademark guidance for third-party apps.

Maker Console itself was not accessed because it requires the publisher's account and acceptance of the Maker Agreement. Console-only choices, including the final organization name, product name, and monetization, therefore remain owner decisions.

## Executive conclusion

The plugin can be submitted through Elgato Maker Console as a `.streamDeckPlugin` file, but the current package should not be submitted yet. It is technically packageable and passes Elgato CLI validation, but it is not release-qualified.

Four items are publication blockers:

1. Freeze a unique product identity and a Marketplace organization name before publication. The manifest author must match the organization, and plugin and action UUIDs cannot be changed after publication.
2. Replace the current runtime `chmod` of the bundled helper with a design compatible with Marketplace DRM file immutability, then test the Maker Console processed build.
3. Replace the ad-hoc, Apple-silicon-only helper with a distribution-signed build and settle the Intel Mac support policy. Developer ID signing and notarization are strongly recommended for a public macOS release.
4. Complete live testing in real Teams meetings, including Accessibility permission attribution, two-party reaction delivery, each stateful control, and the safe Leave Call behavior.

The listing package also needs a 288 x 288 app icon, a 1920 x 960 thumbnail, at least three gallery items, final English listing copy of at least 250 characters, release notes, support information, and an intellectual-property and third-party-license review.

## Current readiness snapshot

The following checks were run in `teams-reactions/` on 2026-09-02 against the current working tree.

| Area | Current result | Publication meaning |
| --- | --- | --- |
| Automated tests | `npm test` passed: 14 Node tests, native regression tests, and TypeScript checking | Good release baseline, but not a substitute for live Teams testing |
| Build | `npm run build` passed | Node plugin and native helper build reproducibly on the current Apple silicon machine |
| Elgato validation | Cached and forced current-schema validation passed with Stream Deck CLI 1.9.0 | Manifest and packaged assets meet the current CLI structural checks |
| Packaging | `npm run pack` produced a 50-file, 253,267-byte package | Upload format is correct |
| Package | `release/com.laurens-bolle.teams-reactions.streamDeckPlugin` | SHA-256 at this snapshot: `1a139f2ce2447922d5f689fcd22e1748ef330dd582f9d50b19884c586552b350` |
| Manifest | Version `0.2.0.0`, SDK 3, Stream Deck 7.1+, Node.js 24, macOS 13+ | Meets Elgato's current DRM baseline |
| Stream Deck SDK | `@elgato/streamdeck` 2.1.2 | Meets the DRM requirement of SDK package v2 or newer |
| Internal plugin icon | PNG at 256 x 256 and 512 x 512 | Correct for the icon referenced by the manifest |
| Category icon | PNG at 28 x 28 and 56 x 56 | Correct dimensions for the action list |
| Native helper | Thin `arm64` Mach-O with an ad-hoc signature | Not ready for a broad public macOS release |
| Helper archive mode | Stored as `0644` in the `.streamDeckPlugin` archive | The current code must change its mode before launch |
| Marketplace media | No separate listing-media set was found | 288 x 288 app icon, thumbnail, and gallery assets still need to be made |
| Legal files | No repository `LICENSE`, `NOTICE`, or third-party notice file was found | Ownership and bundled MIT notices need to be settled before release |

The manifest already has several good properties: all action UUIDs are prefixed by the plugin UUID, names and tooltips are concise, plugin and category names match, failure paths use `showAlert`, and successful operations use state updates or `showOk`. There are nine actions, inside Elgato's recommended range of 2 to 30.

This snapshot does not mean the branch is otherwise clean. The checkout already contained uncommitted implementation and documentation changes before this research file was added.

## Publication blockers and recommended resolutions

### 1. Create the Maker identity and freeze the product identity

Elgato requires the publisher to create an organization in [Maker Console](https://maker.elgato.com/) and sign the Maker Agreement before submitting a product. The `Author` value in the plugin manifest must match that Marketplace organization. See [Become a Maker](https://docs.elgato.com/marketplace/become-a-maker/) and [Plugin Guidelines](https://docs.elgato.com/guidelines/stream-deck/plugins/).

Before creating the product:

1. Decide whether the publisher is `Laurens Bolle`, `Aerodynamite`, or another legal or trading identity.
2. Create the Maker Console organization with that exact display name.
3. Make the manifest `Author` exactly match it.
4. Check the final product name in Marketplace and Maker Console.
5. Freeze the plugin UUID and every action UUID.

This matters because Elgato says a published UUID cannot be changed. The current UUID, `com.laurens-bolle.teams-reactions`, reflects the original reactions-only scope, while the product is now a broader meeting-control plugin. If it will ever be renamed, the safest time is before the first upload. A consistent candidate would be based on the final organization and product, for example `com.laurens-bolle.meeting-deck`. That is only an example and must not be adopted until the organization and name are final.

#### Name and trademark risk

Marketplace already contains products called [Teams Control](https://marketplace.elgato.com/product/teams-control-38fe5bc8-6828-475b-829c-6a9cc266fb67) and [Arise Teams Controller](https://marketplace.elgato.com/product/arise-teams-controller-0f067f3c-7932-424e-8106-b11d9b765b62). `Teams Meeting Controls` is not an exact match in the public search reviewed for this document, but it is close to existing names and begins with a Microsoft product mark.

Microsoft's [Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) say that, without a license, an app's name, logo, and collateral should be unique and free of Microsoft brand assets. The guidance allows a truthful compatibility statement in descriptive text. Microsoft's more specific [app-name guidance](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/trademark-and-copyright-protection) also recommends that an app name not begin with the Microsoft product name and permits phrases such as "for" or "works with" when necessary.

The lowest-risk approach is therefore:

- choose an independent product name, such as a checked and available variant of `Meeting Deck` or `Call Companion`;
- use `Microsoft Teams` only in the description to explain compatibility;
- keep the current custom visual identity and do not use the Microsoft or Teams logo, icon, font treatment, or screenshots without the necessary rights; and
- state that the product is independent and is not affiliated with or endorsed by Microsoft.

Name availability and legal clearance are separate checks. Finding no exact Marketplace search result is not a trademark clearance opinion.

### 2. Make helper execution compatible with Marketplace DRM

Elgato's [distribution documentation](https://docs.elgato.com/streamdeck/sdk/introduction/distribution/) says Marketplace plugins using DRM must treat distributed files as immutable. It specifically says not to modify files after distribution. Node plugins must use `@elgato/streamdeck` v2 or newer, SDK version 3, and Stream Deck minimum version 6.9 or newer.

This plugin meets the SDK and manifest requirements, but it has a packaging conflict:

- Elgato CLI stores every file, including `bin/teams-reaction`, as `0644` in the generated archive.
- [`helper-runner.ts`](../../teams-reactions/src/helper-runner.ts) calls `chmodSync` on that bundled file before every launch.
- The local workaround succeeds outside DRM, but it modifies a distributed file and has not been tested after Maker Console DRM processing.

Treat this as a release blocker. A structural fix is preferable to hoping that DRM ignores mode changes.

Recommended implementation direction:

1. Keep the packaged helper bytes read-only.
2. On first use, copy the helper into an owner-only runtime directory outside the protected plugin bundle, such as `~/Library/Application Support/<final-plugin-uuid>/runtime/<version-or-digest>/teams-reaction`.
3. Reject symlinks, copy atomically, set the copied file to `0700`, and verify its expected SHA-256 before execution.
4. Execute only that fixed, verified path with the existing allow-listed arguments.
5. Retain a stable path and stable signing identity so the Accessibility permission does not needlessly change across launches.
6. Clean old runtime versions conservatively after a successful upgrade.

This is a proposed design, not a confirmed Elgato pattern. Ask `maker@elgato.com` whether Maker Console has an approved way to preserve executable mode for bundled native helpers. Regardless of the answer, upload an early build with automatic publication disabled, download the DRM-processed version from its Versions tab, and test that exact build. Elgato explicitly documents this unpublished DRM test flow.

### 3. Distribution-sign and qualify the native macOS helper

The current helper is ad-hoc signed and contains only an `arm64` slice. That is suitable for local development, but weak for software distributed to unknown Macs:

- an ad-hoc signature has no publisher identity;
- the Accessibility permission may be less stable across rebuilds;
- an Intel Mac cannot execute the helper; and
- the manifest can declare macOS support but has no CPU-architecture field.

Apple's [Developer ID documentation](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) describes Developer ID signing for software distributed outside the Mac App Store. Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) calls for a Developer ID Application signature, hardened runtime, a secure timestamp, and notarization for current public macOS distribution.

Recommended release target:

- build a universal helper containing `arm64` and `x86_64` slices;
- sign it with the publisher's Developer ID Application certificate, hardened runtime, stable identifier, and timestamp;
- notarize it using an Apple-supported container and verify the notarization result;
- verify the unchanged helper after it is copied to the runtime directory;
- test on both Apple silicon and Intel hardware, including a fresh macOS user account; and
- confirm that the Marketplace-processed download launches without Gatekeeper warnings beyond the expected Accessibility consent.

If Intel support is deliberately excluded, say `Apple silicon only` in the first 250 characters of the listing, requirements, gallery, and support page. Before choosing that route, ask Maker Relations whether an architecture-limited macOS plugin is acceptable because the manifest cannot express that limit.

Elgato's public plugin guidelines reviewed for this document do not state a specific Developer ID or notarization rule for a bundled helper. The recommendation above follows Apple's distribution requirements and reduces review, Gatekeeper, and Accessibility-identity risk. It should be confirmed with Elgato before the release pipeline is finalized.

### 4. Complete live qualification

The automated tests prove safe selection against fixtures and validate process coordination. They do not prove that the installed plugin controls the current Teams client or that another participant sees a reaction.

At minimum, qualify the final signed and DRM-processed package against this matrix:

| Dimension | Minimum coverage |
| --- | --- |
| Package source | Local release package and Maker Console DRM-processed package |
| macOS | Oldest declared version, currently macOS 13, plus the current supported release |
| CPU | Apple silicon and Intel if the listing claims general Mac support |
| Stream Deck | Minimum declared version 7.1 plus the current release |
| Teams | Current production desktop client with bundle identifier `com.microsoft.teams2` |
| Locale | English, Dutch, German, French, and Spanish, or narrow the supported-locale claim |
| Permission state | No Accessibility permission, newly granted permission, revoked permission, and permission after plugin update |
| Meeting state | Teams closed, Teams open outside a meeting, active meeting, controls hidden, and meeting ended |
| Controls | Mute and unmute, camera on and off, raise and lower hand, and Leave Call in a disposable meeting |
| Reactions | Each of the five reactions, normal tap, rapid competing taps, and long-press behavior |
| External confirmation | A second participant or device confirms reaction delivery and state changes |
| Failure UX | Unavailable and ambiguous controls show an alert or explicit unknown state, never a false success state |
| Logs | No meeting titles, participant names, helper stdout, credentials, or other personal data |

Capture the results in [`docs/testing/teams-call-controls.md`](../testing/teams-call-controls.md). The final test should use a clean machine or clean user account, not only the development machine that already has permissions and linked builds.

#### Reaction-wave release risk

The long-press reaction wave sends up to three attempts per second for three seconds. Its native limits are good defensive controls, but repeated reactions may be viewed as disruptive, may be throttled by Teams, and have not yet been proven end to end. This is an inference from the behavior, not an Elgato rule found in the reviewed documentation.

For the lowest-risk first release, either ship single-reaction presses only or demonstrate in the review video that a bounded hold behaves predictably and is easy to stop. Do not advertise every attempted reaction as delivered unless a second participant confirms that behavior.

## Marketplace listing and media package

Elgato's [Submitting Products](https://docs.elgato.com/maker-console/submitting-products/) and [Product Guidelines](https://docs.elgato.com/guidelines/products/) require the following for a Stream Deck plugin submission.

| Deliverable | Official requirement | Current state and action |
| --- | --- | --- |
| Plugin installer | `.streamDeckPlugin` uploaded through Maker Console | Generated successfully, but rebuild after all blockers are fixed |
| Product name | Unique, English, concise, ideally 30 characters or fewer | Freeze a legally safe independent name before creating the product |
| Description | English, 250 to 1,500 characters, first 250 characters plain text, features and requirements included | Current manifest description is too short and must be replaced |
| Internal plugin icon | PNG, 256 x 256 plus 512 x 512 high-DPI version | Present and dimensionally correct |
| Marketplace app icon | Static PNG, 288 x 288 | Missing as a separate submission asset |
| Thumbnail | PNG, 1920 x 960 | Missing |
| Gallery | At least 3 and up to 10 items; images are 1920 x 960 PNG, video is 1920 x 1080 MP4 | Missing |
| Release notes | English summary of the submitted version | Missing |
| Additional links | Support, setup, demo, website, and privacy links where relevant | Add a durable support URL and setup guide |
| Pricing | Free or paid, with Marketplace rules applied | Decide before product creation; Elgato says name and monetization cannot be changed directly in Maker Console afterward |
| Rights | Publisher must own or have permission for all code, names, imagery, screenshots, and product files | Document icon provenance and audit all bundled material |
| Data and security | Explicit consent and privacy policy if analytics or identifiable data is collected | Plugin claims no collection; verify code and publish a short no-collection privacy statement |

The 288 x 288 Marketplace app icon is distinct from the 256 x 256 and 512 x 512 icon embedded in the plugin. Reusing the same original artwork is reasonable, but export and inspect the exact required size.

Recommended gallery set:

1. A clean hero image showing the independently branded plugin and its available actions on a real Stream Deck.
2. A functional image showing mute, camera, hand, and safe leave states, with minimal English text.
3. A privacy and setup image explaining local-only operation and the one-time macOS Accessibility permission.
4. A short demonstration video showing a physical key press, the Teams UI response, state feedback on Stream Deck, and a second participant receiving a reaction.

Elgato says a demonstration video is required for products that depend on hardware or paid-service integrations. Even if Maker Console does not enforce that rule for this plugin, supplying a concise video is prudent because the native Accessibility integration cannot be validated from screenshots. Keep all meeting names and participant data out of the recording.

### Proposed listing copy

Use this only after the final name, architecture policy, and feature set are decided.

**Working title:** `Meeting Deck`

**Description draft:**

> Meeting Deck gives macOS users fast, local control of Microsoft Teams meetings from Stream Deck. Mute or unmute, switch the camera, raise or lower your hand, leave safely, and send five reactions without storing Teams credentials or sending meeting data to a separate service. It requires macOS 13 or later, Stream Deck 7.1 or later, the Microsoft Teams desktop app, and one-time Accessibility permission. The plugin is independently developed and is not affiliated with or endorsed by Microsoft.

If the first release remains Apple silicon only, add that requirement near the start rather than burying it.

**Release notes draft:**

> Initial release. Adds local macOS controls for microphone, camera, raised hand, safe meeting leave, and five reactions. Includes clear success, failure, unavailable, and unknown-state feedback. Requires the Microsoft Teams desktop app and macOS Accessibility permission.

### Support and privacy material

Publish a stable support page before submission. A repository README is acceptable only if its URL will remain public and maintained. It should include:

- installation and Accessibility permission steps;
- supported macOS, CPU, Stream Deck, Teams, and language versions;
- how to find and safely share privacy-filtered logs;
- expected failure behavior outside a meeting;
- removal and permission-revocation instructions;
- a security contact or issue path; and
- a clear statement about data collection, networking, and retention.

The current package bundles MIT-licensed JavaScript dependencies, including `@elgato/streamdeck`, `@elgato/schemas`, `@elgato/utils`, `ws`, and `zod`. Add a project license and generate a reviewed `THIRD_PARTY_NOTICES` file containing the required notices. Decide whether the notices belong in the plugin package, the public repository, the support page, or more than one location based on the license text and legal advice.

## Exact Maker Console submission flow

Once the blockers are closed:

1. Go to [Maker Console](https://maker.elgato.com/), create the publishing organization, and sign the Maker Agreement.
2. Select **Create product** and choose **Stream Deck plugin**.
3. Confirm the final name and whether the product is free or paid. Elgato warns that these choices cannot be changed directly in Maker Console later.
4. Upload the final `.streamDeckPlugin` file.
5. Review the imported name and description, then add accurate macOS, compatibility, category, pricing, and additional-link details.
6. Upload the 288 x 288 app icon, 1920 x 960 thumbnail, and at least three gallery items.
7. Add release notes.
8. Leave automatic publication disabled for the first submission.
9. Submit for review. Elgato says every new product and version is reviewed and advises allowing 4 to 10 working days.
10. Respond to feedback sent from `maker@elgato.com`. A rejected version can be revised and resubmitted.
11. In the product's **Versions** tab, download the DRM-processed build and run the complete clean-machine qualification matrix.
12. After approval and successful DRM testing, release the approved version manually. Elgato notes that publication may take up to three hours to appear.

For subsequent releases, increase the four-part manifest version, package a clean build, add release notes, submit the new version for review, test the processed build, and release it. Only the newest approved version is offered to users.

## Release command sequence

Run the release from a clean checkout of the intended commit. Do not publish directly from the current dirty feature worktree.

```sh
cd teams-reactions
npm ci
npm test
npm audit --omit=dev
npm run build
npx streamdeck validate com.laurens-bolle.teams-reactions.sdPlugin --force-update-check
npm run pack
shasum -a 256 release/com.laurens-bolle.teams-reactions.streamDeckPlugin
```

Replace the old UUID in these commands if the pre-publication identity is changed. Also verify:

```sh
file com.laurens-bolle.teams-reactions.sdPlugin/bin/teams-reaction
codesign --verify --deep --strict --verbose=2 com.laurens-bolle.teams-reactions.sdPlugin/bin/teams-reaction
codesign -dv --verbose=4 com.laurens-bolle.teams-reactions.sdPlugin/bin/teams-reaction
```

The final CI or release job should fail if tests, current-schema validation, signature verification, expected architectures, package inventory, or checksums differ from the release policy.

## Go or no-go checklist

### Publisher and identity

- [ ] Maker Console organization created.
- [ ] Maker Agreement reviewed and signed by the authorized publisher.
- [ ] Final product name checked for Marketplace uniqueness and trademark risk.
- [ ] Manifest author exactly matches the organization.
- [ ] Final plugin and action UUIDs chosen and treated as permanent.
- [ ] Free or paid decision made.

### Code and packaging

- [ ] Runtime no longer modifies files inside the distributed plugin bundle.
- [ ] Maker Relations confirms the native-helper packaging approach, if needed.
- [ ] Helper is Developer ID signed with hardened runtime and timestamp.
- [ ] Helper notarization workflow succeeds.
- [ ] Universal binary built and tested, or Apple-silicon-only limitation accepted and disclosed.
- [ ] Project license and third-party notices reviewed.
- [ ] `npm ci`, tests, audit, build, current-schema validation, and pack all pass from a clean checkout.
- [ ] Final package inventory and SHA-256 recorded.

### Product qualification

- [ ] Clean-machine Accessibility onboarding succeeds.
- [ ] Accessibility permission survives relaunch and update as designed.
- [ ] Mute, camera, hand, and Leave Call pass both normal and failure tests.
- [ ] All five reactions are confirmed by another participant or device.
- [ ] Long-press behavior is either removed from v1 or explicitly qualified.
- [ ] No private meeting data appears in logs or media.
- [ ] DRM-processed package passes the same matrix as the local package.

### Listing

- [ ] Description is 250 to 1,500 English characters and includes every requirement.
- [ ] 288 x 288 app icon is independently branded and rights-cleared.
- [ ] 1920 x 960 thumbnail is complete.
- [ ] At least three gallery items are complete.
- [ ] Demonstration video is complete and privacy-clean.
- [ ] Release notes are accurate.
- [ ] Support, setup, privacy, and contact links are live.
- [ ] OS, CPU, Stream Deck, Teams, and language claims match tested evidence.

### Submission

- [ ] Automatic publication is disabled for the first review.
- [ ] Review feedback owner is assigned and monitors the Maker email address.
- [ ] DRM-processed download is tested before manual release.
- [ ] Rollback and follow-up release process is documented.

## Recommended order of work

1. Create the Maker organization and decide the final independent product name.
2. Rename the UUID before publication if the broader product identity will be permanent.
3. Redesign helper staging so the packaged bundle remains immutable.
4. Add Developer ID signing, notarization, and a universal native build.
5. Finish live qualification and decide whether reaction waves belong in version 1.
6. Add license, notices, support, privacy, and Marketplace listing copy.
7. Produce the listing media and demonstration video from the qualified build.
8. Make a clean release package, upload with automatic publication disabled, and test the processed DRM build.
9. Submit, allow 4 to 10 working days for review, address feedback, and release manually after approval.

## Primary sources

- [Elgato: Become a Maker](https://docs.elgato.com/marketplace/become-a-maker/)
- [Elgato: Submitting Products](https://docs.elgato.com/maker-console/submitting-products/)
- [Elgato: Review Process](https://docs.elgato.com/maker-console/review-process/)
- [Elgato: Product Guidelines](https://docs.elgato.com/guidelines/products/)
- [Elgato: Branding Guidelines](https://docs.elgato.com/guidelines/branding/)
- [Elgato: Stream Deck Plugin Guidelines](https://docs.elgato.com/guidelines/stream-deck/plugins/)
- [Elgato: Plugin Distribution and DRM](https://docs.elgato.com/streamdeck/sdk/introduction/distribution/)
- [Elgato: Manifest Reference](https://docs.elgato.com/streamdeck/sdk/references/manifest/)
- [Elgato: Stream Deck CLI pack](https://docs.elgato.com/streamdeck/cli/commands/pack/)
- [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Microsoft: Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)
- [Microsoft: App naming and trademark guidance](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/trademark-and-copyright-protection)

## Research limits

- The Maker Agreement is visible only inside the publisher's organization settings and was not reviewed here.
- No legal opinion is offered. Final trademark, license, privacy, tax, and commercial decisions belong to the publisher and their advisers.
- No claim is made that Elgato requires Developer ID signing or notarization for this exact helper layout. Those are Apple distribution controls and prudent release requirements that should be confirmed with Maker Relations.
- Marketplace rules change. Re-run current-schema validation and recheck the linked guidelines immediately before submission.
