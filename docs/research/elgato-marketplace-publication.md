# Publishing Teams Meeting Controls on Elgato Marketplace

Last reviewed: 2026-09-23. Original research: 2026-09-02.

## Scope

This document applies to **Teams Meeting Controls** on `main`, inspected at commit `ed3fdf5c1187c16e8c6e87270886a5565abb2622`. The checkout was clean before this documentation review. The meeting-control feature has been merged. Version `0.2.0.0` exposes nine actions: Mute, Camera, Raise Hand, Leave Call, and five reactions.

Commit `1ce835b` added recognition of the live `Mute mic` and `Unmute mic` labels and removed Background Blur from the manifest, action registration, and packaged images. Experimental blur commands remain in the native helper, but are not a listing feature. These code changes do not establish completion of the live qualification matrix, whose results still read `Not run`.

The conclusions combine:

- the current manifest, package, native helper, tests, and documentation in this repository;
- the Elgato Marketplace and Stream Deck SDK documentation checked on 2026-09-23;
- Apple's current guidance for distributing macOS executables outside the Mac App Store; and
- Microsoft's current trademark guidance for third-party apps.

Maker Console itself was not accessed. Organization setup, agreement acceptance, product creation, prior uploads, and publication status cannot be inferred from the checkout. Confirm those account facts before renaming identifiers or creating a product; the recommendations below assume a first publication only if no existing product already uses this identity.

## Executive conclusion

The plugin builds, passes its automated tests and Elgato CLI validation, and produces a `.streamDeckPlugin` file. It is not ready for public release. An unpublished upload can be used to test Marketplace processing once the publisher identity is settled.

The remaining release gates are:

1. Freeze a unique product identity and a Marketplace organization name before publication. The manifest author must match the organization, and plugin and action UUIDs cannot be changed after publication.
2. Resolve native compatibility: the helper rebuilt during this review has a macOS **27.0** deployment target, despite the manifest claiming **13+**, and contains only `arm64`. Set an explicit deployment target and settle the Intel support policy.
3. Qualify helper execution in the Maker Console processed build. The conditional runtime `chmod` is an unresolved DRM compatibility question, not a proven DRM failure.
4. Complete live testing in real Teams meetings, including Accessibility permission attribution, two-party reaction delivery, each stateful control, and the safe Leave Call behavior.
5. Establish a distribution-signing and notarization workflow. This is the recommended public-release policy, not a helper-specific Elgato rule established by the public documentation.

The listing package also needs a 288 x 288 app icon, a 1920 x 960 thumbnail, at least three gallery items, final English listing copy of at least 250 characters, release notes, support information, and an intellectual-property and third-party-license review.

## Current readiness snapshot

The following checks were run in `teams-reactions/` on 2026-09-23 using the installed dependencies: Node.js `24.13.1`, npm `11.16.0`, Stream Deck CLI `1.9.0`, and TypeScript `5.9.3`. `npm ci` was not rerun, so this is a local verification snapshot, not proof of a fresh-install release build.

| Area | Current result | Publication meaning |
| --- | --- | --- |
| Automated tests | `npm test` passed: 14 Node tests, native regression tests, and TypeScript checking | Good release baseline, but not a substitute for live Teams testing |
| Build | `npm run build` passed | Local build succeeds; cross-machine reproducibility is not established |
| Elgato validation | Cached and forced current-schema validation passed with Stream Deck CLI 1.9.0 | Manifest and packaged assets meet the current CLI structural checks |
| Packaging | `npm run pack` produced a 50-file, 252,713-byte package | Upload format is correct; this remains a development artifact |
| Package | `release/com.laurens-bolle.teams-reactions.streamDeckPlugin` | SHA-256 at this snapshot: `3bbf48b3861ab23a18b1a3d2663fbe65a1b1194014dd21c2b16767fa4fa41085` |
| Production dependency audit | `npm audit --omit=dev` reported 0 vulnerabilities | Point-in-time registry result; excludes development dependencies and does not establish license compliance |
| Manifest | Version `0.2.0.0`, SDK 3, Stream Deck 7.1+, Node.js 24, macOS 13+ | Meets Elgato's current DRM baseline |
| Stream Deck SDK | `@elgato/streamdeck` 2.1.2 | Meets the DRM requirement of SDK package v2 or newer |
| Internal plugin icon | PNG at 256 x 256 and 512 x 512 | Correct for the icon referenced by the manifest |
| Category icon | PNG at 28 x 28 and 56 x 56 | Correct dimensions for the action list |
| Native helper | Thin `arm64` Mach-O with an ad-hoc signature | Not ready for a broad public macOS release |
| Native deployment target | `xcrun vtool -show-build` reports `minos 27.0`, SDK `27.0` | Contradicts manifest macOS 13+; the build script does not set a minimum target |
| Signature verification | `codesign --verify --strict` passed; `Signature=adhoc`, no TeamIdentifier | Integrity check passes, but this is not Developer ID signing or notarization |
| Helper archive mode | Stored as `0644` in the `.streamDeckPlugin` archive | The current code must change its mode before launch |
| Marketplace media | No separate listing-media set was found | 288 x 288 app icon, thumbnail, and gallery assets still need to be made |
| Legal files | No repository `LICENSE`, `NOTICE`, or third-party notice file was found | Ownership and bundled MIT notices need to be settled before release |
| Live qualification | All recorded result fields remain `Not run` | No completed release qualification is evidenced in the repository |

The manifest already has several good properties: all action UUIDs are prefixed by the plugin UUID, names and tooltips are concise, plugin and category names match, failure paths use `showAlert`, and successful operations use state updates or `showOk`. There are nine actions, inside Elgato's recommended range of 2 to 30.

The first forced-schema check could not reach Elgato and still printed success using local schemas. A subsequent network-enabled `--force-update-check` passed without remote-schema warnings. A release check must inspect those warnings, not just the exit code. Package size and checksum identify only this local artifact; record them again after any rebuild or signing step.

## Publication blockers and recommended resolutions

### 1. Create the Maker identity and freeze the product identity

Elgato requires the publisher to create an organization in [Maker Console](https://maker.elgato.com/) and sign the Maker Agreement before submitting a product. The `Author` value in the plugin manifest must match that Marketplace organization. See [Become a Maker](https://docs.elgato.com/marketplace/become-a-maker/) and [Plugin Guidelines](https://docs.elgato.com/guidelines/stream-deck/plugins/).

Before creating the product:

1. Confirm the publisher identity. The current manifest author is `Laurens Bolle`; account ownership and organization name were not verified.
2. Confirm or create the Maker Console organization with that exact display name.
3. Make the manifest `Author` exactly match it.
4. Check the final product name in Marketplace and Maker Console.
5. Freeze the plugin UUID and every action UUID.

This matters because Elgato says a published UUID cannot be changed. The current UUID, `com.laurens-bolle.teams-reactions`, reflects the original scope, but that does not itself require a rename. Keep it unless a pre-publication identity change is deliberately chosen. If no product has been published, a candidate such as `com.laurens-bolle.meeting-deck` could be considered after the name is settled. A UUID change also affects existing profiles and installed development copies.

#### Name and trademark risk

Marketplace has public listings for [Teams Control](https://marketplace.elgato.com/product/teams-control-38fe5bc8-6828-475b-829c-6a9cc266fb67) and [Arise Teams Controller](https://marketplace.elgato.com/product/arise-teams-controller-0f067f3c-7932-424e-8106-b11d9b765b62). `Teams Meeting Controls` is close to those names and begins with a Microsoft product mark. This review does not establish name availability.

Microsoft's [Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) say that, without a license, an app's name, logo, and collateral should be unique and free of Microsoft brand assets. The guidance allows a truthful compatibility statement in descriptive text. Its [Windows app-name guidance](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/trademark-and-copyright-protection) also discusses compatibility wording, but is not an Elgato policy or automatic clearance for this macOS plugin.

The lowest-risk approach is therefore:

- choose an independent product name, such as a checked and available variant of `Meeting Deck` or `Call Companion`;
- use `Microsoft Teams` only in the description to explain compatibility;
- keep the current custom visual identity and do not use the Microsoft or Teams logo, icon, font treatment, or screenshots without the necessary rights; and
- state that the product is independent and is not affiliated with or endorsed by Microsoft.

Name availability and legal clearance are separate checks. Finding no exact Marketplace search result is not a trademark clearance opinion.

### 2. Make helper execution compatible with Marketplace DRM

Elgato's [distribution documentation](https://docs.elgato.com/streamdeck/sdk/introduction/distribution/) says Marketplace plugins using DRM must treat distributed files as immutable. It specifically says not to modify files after distribution. Node plugins must use `@elgato/streamdeck` v2 or newer, SDK version 3, and Stream Deck minimum version 6.9 or newer.

This plugin meets the SDK and manifest DRM baseline, but native execution still needs qualification:

- The inspected CLI 1.9.0 archive stores every file, including `bin/teams-reaction`, as `0644`.
- [`helper-runner.ts`](../../teams-reactions/src/helper-runner.ts) checks the mode before each normal or burst launch and calls `chmodSync(..., 0755)` only when execute bits are missing. Automated tests cover both paths.
- This changes permission metadata, not executable bytes. Elgato's public DRM documentation does not say whether permission metadata is checked. No processed-build test is recorded.

The release gate is evidence that helper launch works under Marketplace processing. Do not describe the current approach as a confirmed DRM violation or assume relocation is mandatory. Ask Maker Relations whether executable permissions can be preserved or restored, and test the processed build before choosing a redesign.

If the current approach is rejected or fails, one design to evaluate is:

1. Keep the packaged helper bytes read-only.
2. On first use, copy the helper into an owner-only runtime directory outside the protected plugin bundle, such as `~/Library/Application Support/<final-plugin-uuid>/runtime/<version-or-digest>/teams-reaction`.
3. Reject symlinks, copy atomically, set the copied file to `0700`, and verify its expected SHA-256 before execution.
4. Execute only that fixed, verified path with the existing allow-listed arguments.
5. Use a stable signing identity and explicitly test permission retention across updates. A version- or digest-specific path changes on upgrade, so this layout alone does not guarantee stable Accessibility authorization.
6. Clean old runtime versions conservatively after a successful upgrade.

This is a proposed design, not a confirmed Elgato pattern. Preserve the allow-listed arguments, single-operation lock, bounded reaction sessions, and cancellation on release in any implementation. Upload an early build with automatic publication disabled, download the DRM-processed version from its Versions tab, and test that exact build. Elgato explicitly documents this unpublished DRM test flow.

### 3. Distribution-sign and qualify the native macOS helper

The rebuilt helper currently declares `LC_BUILD_VERSION minos 27.0`, while the manifest and README say macOS 13+. [`build-native.sh`](../../teams-reactions/scripts/build-native.sh) passes neither an explicit deployment target nor architecture flags to clang, so the host toolchain determines both. Set an explicit target such as `-mmacosx-version-min=13.0` if macOS 13 remains supported, check API availability, inspect every resulting architecture slice, and test on that minimum OS. Changing the manifest alone does not lower the executable's minimum version.

The current helper is ad-hoc signed and contains only an `arm64` slice. That is suitable for local development, but weak for software distributed to unknown Macs:

- an ad-hoc signature has no publisher identity;
- the Accessibility permission may be less stable across rebuilds;
- an Intel Mac cannot execute the helper; and
- the manifest can declare macOS support but has no CPU-architecture field.

Apple's [Developer ID documentation](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) describes Developer ID signing for software distributed outside the Mac App Store. Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) calls for a Developer ID Application signature, hardened runtime, a secure timestamp, and notarization for current public macOS distribution.

Recommended release target:

- build a universal helper containing `arm64` and `x86_64` slices;
- set and verify the deployment target so the executable and manifest agree;
- sign it with the publisher's Developer ID Application certificate, hardened runtime, stable identifier, and timestamp;
- notarize it using an Apple-supported container and verify the notarization result;
- verify the helper after packaging and installation, and after copying if runtime staging is adopted;
- test on both Apple silicon and Intel hardware, including a fresh macOS user account; and
- confirm that the Marketplace-processed download launches without Gatekeeper warnings beyond the expected Accessibility consent.

If Intel support is deliberately excluded, say `Apple silicon only` in the first 250 characters of the listing, requirements, gallery, and support page. Before choosing that route, ask Maker Relations whether an architecture-limited macOS plugin is acceptable because the manifest cannot express that limit.

Elgato's public plugin guidelines reviewed for this document do not state a specific Developer ID or notarization rule for a bundled helper. The recommendation above follows Apple's distribution requirements and reduces review, Gatekeeper, and Accessibility-identity risk. It should be confirmed with Elgato before the release pipeline is finalized.

Signing and notarization are separate checks. A successful `codesign --verify` also accepts the current ad-hoc signature and does not prove either Developer ID identity or notarization. Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) explains container handling; a bare command-line executable or ZIP cannot have a ticket stapled directly to it. Choose the supported submission container and verify actual installed launch behavior rather than assuming the final `.streamDeckPlugin` archive is an Apple notarization format.

Also change the release sequencing before introducing production signing: `npm run pack` invokes `npm run build`, and `build:native` always signs with `--sign -`. Manually signing the helper and then running the current pack script would replace it with a newly built, ad-hoc-signed helper.

### 4. Complete live qualification

The automated tests prove safe selection against fixtures and validate process coordination. They do not prove that the installed plugin controls the current Teams client or that another participant sees a reaction. No live meeting actions were performed during this review. Core controls, safe leave in attendee and organizer roles, permission onboarding and upgrades, window variants, locales, and second-participant reaction delivery all remain unverified by the recorded matrix.

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
| Description | Marketplace listing: English, 250 to 1,500 characters, first 250 characters plain text, features and requirements included | Manifest has a short summary; expand the imported text in Maker Console for the listing. This is not a manifest-schema minimum |
| Internal plugin icon | PNG, 256 x 256 plus 512 x 512 high-DPI version | Present and dimensionally correct |
| Marketplace app icon | Static PNG, 288 x 288 | Missing as a separate submission asset |
| Thumbnail | PNG, 1920 x 960 | Missing |
| Gallery | At least 3 and up to 10 items; images are 1920 x 960 PNG, video is 1920 x 1080 MP4 under 250 MB | Missing |
| Release notes | English summary of the submitted version | Draft below; final submission notes not verified |
| Additional links | Support, setup, demo, website, and privacy links where relevant | Add a durable support URL and setup guide |
| Pricing | Free or paid, with Marketplace rules applied | Account choice unverified; changes to name or monetization after creation require Maker Relations rather than self-service editing |
| Rights | Publisher must own or have permission for all code, names, imagery, screenshots, and product files | Document icon provenance and audit all bundled material |
| Data and security | Explicit consent and privacy policy if analytics or identifiable data is collected | Plugin claims no collection; verify code and publish a short no-collection privacy statement |

The 288 x 288 Marketplace app icon is distinct from the 256 x 256 and 512 x 512 icon embedded in the plugin. Reusing the same original artwork is reasonable, but export and inspect the exact required size.

Recommended gallery set:

1. A clean hero image showing the independently branded plugin and its available actions on a real Stream Deck.
2. A functional image showing mute, camera, hand, and safe leave states, with minimal English text.
3. A privacy and setup image explaining local-only operation and the one-time macOS Accessibility permission.
4. A short demonstration video showing a physical key press, the Teams UI response, state feedback on Stream Deck, and a second participant receiving a reaction.

Elgato's [Review Process](https://docs.elgato.com/maker-console/review-process/) requires a demonstration video for products that depend on hardware or paid-service integrations. Confirm applicability with Maker Relations; supplying a concise video is recommended for this Accessibility integration. Keep all meeting names and participant data out of the recording, and clear the rights to any Teams imagery before using it in public media.

### Proposed listing copy

Use this only after the final name, architecture policy, and feature set are decided. The draft assumes that the macOS 13 deployment target has been fixed and qualified; it does not describe the current local binary accurately.

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

The installed production dependency tree contains MIT-licensed `@elgato/streamdeck` 2.1.2, `@elgato/schemas` 0.4.16, `@elgato/utils` 0.6.0, `ws` 8.21.3, and `zod` 3.25.76. Audit what Rollup actually includes and ship the applicable copyright and permission notices with the distributed plugin. A support-page link alone should not be assumed to satisfy the MIT requirement to include notices in copies or substantial portions of the software. Choose and document terms for the project's own code separately; Marketplace publication does not itself establish a requirement to open-source it. No notice file was present in the inspected archive.

## Maker Console submission flow

The [submission guide](https://docs.elgato.com/maker-console/submitting-products/), [review process](https://docs.elgato.com/maker-console/review-process/), and [DRM testing instructions](https://docs.elgato.com/streamdeck/sdk/introduction/distribution/#testing-with-drm) describe this flow. Confirm the account's existing state first. An unpublished processed-build test can happen before all release gates close; public release must wait for them.

1. Go to [Maker Console](https://maker.elgato.com/), confirm or create the publishing organization, and ensure the Maker Agreement is signed.
2. For a new product, select **Create product** and choose **Stream Deck plugin**. Use the existing product if one is already associated with this plugin.
3. Confirm the final name and whether the product is free or paid. Elgato warns that these choices cannot be changed directly in Maker Console later.
4. Upload the candidate `.streamDeckPlugin` file.
5. Review the imported name and description, then add accurate macOS, compatibility, category, pricing, and additional-link details.
6. Upload the 288 x 288 app icon, 1920 x 960 thumbnail, and at least three gallery items.
7. Add release notes.
8. Leave automatic publication disabled for the first submission.
9. In the product's **Versions** tab, download the processed build when available and run the clean-machine qualification matrix. Elgato documents testing DRM without publishing; the public documentation does not guarantee exactly when the download becomes available relative to review.
10. Submit the release candidate for review. Elgato advises allowing 4 to 10 working days; this is guidance, not a guaranteed deadline.
11. Respond to feedback sent from `maker@elgato.com`. A rejected version can be revised and resubmitted. Re-test any replacement processed build before release.
12. After approval and successful DRM testing, release the approved version manually. Elgato notes that publication may take up to three hours to appear.

For subsequent releases, increase the four-part manifest version, package a clean build, add release notes, submit the new version for review, test the processed build, and release it. Only the newest approved version is offered to users.

## Verification and release command sequence

Run from a clean checkout of the intended commit. The following commands verify the current development package. They do not yet produce a distribution-signed release, because the build script still uses ad-hoc signing.

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

Replace the UUID in these commands only if a pre-publication identity change is chosen. Inspect the final helper and archive:

```sh
file com.laurens-bolle.teams-reactions.sdPlugin/bin/teams-reaction
xcrun vtool -show-build com.laurens-bolle.teams-reactions.sdPlugin/bin/teams-reaction
codesign --verify --strict --verbose=2 com.laurens-bolle.teams-reactions.sdPlugin/bin/teams-reaction
codesign -dv --verbose=4 com.laurens-bolle.teams-reactions.sdPlugin/bin/teams-reaction
zipinfo -l release/com.laurens-bolle.teams-reactions.streamDeckPlugin
```

Before a public release, implement a pipeline that builds the intended architectures and deployment target, signs the final helper with Developer ID, completes notarization, then packages without rebuilding that helper. A direct `npx streamdeck pack com.laurens-bolle.teams-reactions.sdPlugin --force --output release --no-update-check` can package already-prepared contents; the current `npm run pack` cannot preserve a manually signed helper. Verify the extracted final helper and the Marketplace-installed copy, not only the pre-package binary.

The final CI or release job should fail on missing remote schemas, incompatible deployment targets, unexpected architectures, absent Developer ID identity, failed notarization, missing notices, or unexpected archive contents. Record the final package checksum after all mutations. A checksum identifies the artifact; rebuilding does not guarantee the same ZIP bytes.

## Go or no-go checklist

### Publisher and identity

- [ ] Maker Console organization created.
- [ ] Maker Agreement reviewed and signed by the authorized publisher.
- [ ] Final product name checked for Marketplace uniqueness and trademark risk.
- [ ] Manifest author exactly matches the organization.
- [ ] Final plugin and action UUIDs chosen and treated as permanent.
- [ ] Free or paid decision made.

### Code and packaging

- [ ] Helper launch and permission handling are qualified in the DRM-processed package.
- [ ] Maker Relations clarification or test evidence resolves the conditional `chmod` question; redesign only if required.
- [ ] Native deployment target matches the advertised minimum macOS version in every architecture slice.
- [ ] Helper is Developer ID signed with hardened runtime and timestamp.
- [ ] Helper notarization workflow succeeds.
- [ ] Packaging preserves the final signed and notarized helper instead of rebuilding it ad hoc.
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

1. Confirm or create the Maker organization and decide the final independent product name.
2. Confirm whether the UUID has already been published. Keep the existing identifier unless an intentional pre-publication rename is chosen.
3. Fix the native deployment target and decide the CPU support policy. Establish Developer ID signing and notarization without a later ad-hoc rebuild.
4. Upload an unpublished candidate to qualify helper permissions under DRM. Seek Maker Relations clarification and redesign staging only if necessary.
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
- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Microsoft: Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)
- [Microsoft: App naming and trademark guidance](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/trademark-and-copyright-protection)

## Research limits

- The Maker Agreement is visible only inside the publisher's organization settings and was not reviewed here.
- No Maker Console account, processed download, fresh-machine install, or live Teams meeting was inspected. Unchecked account tasks mean unverified, not proof they have not been done.
- The local checks used existing installed dependencies. A fresh `npm ci`, cross-architecture builds, minimum-OS execution, Developer ID signing, and notarization remain release work.
- No legal opinion is offered. Final trademark, license, privacy, tax, and commercial decisions belong to the publisher and their advisers.
- No claim is made that Elgato requires Developer ID signing or notarization for this exact helper layout. Those are Apple distribution controls and prudent release requirements that should be confirmed with Maker Relations.
- Marketplace rules change. Re-run current-schema validation and recheck the linked guidelines immediately before submission.
