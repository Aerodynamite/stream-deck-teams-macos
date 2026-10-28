# Remaining publication questions

Saved: 2026-10-04. All questions below are unanswered.

The publisher asked to receive all follow-up questions together, then paused the interview. Resume with this batch; recommendations below are proposals, not decisions. Answers already given through Q16 are recorded in the [publication plan](publication-plan.md).

## Q17. Support and documentation

Is best-effort support through GitHub Issues, without guaranteed response or fix times, acceptable?

Recommendation: use the existing repository for support, setup instructions, troubleshooting, and privacy information. On 2026-09-30, the GitHub repository was verified as public with Issues enabled; that inspection does not establish a support commitment.

## Q18. Public contact

What email address or contact page should be published for private security reports and requests to sell or bundle the plugin?

Provide a contact intended for public use. Do not infer a public contact from Git author addresses or account credentials.

## Q19. Copyright and contributor permission

Who should be named as the copyright holder: the publisher personally or a legal entity behind Heartbit? Does the publisher have permission from Nicky Goethals to distribute his contributions under the intended license restrictions?

The repository history includes Nicky's executable-permission fix, associated tests, and reload documentation. Authorship does not establish ownership or permission to apply new license terms. If permission is unknown, prepare a request for the publisher to send.

## Q20. Artwork and branding

Are the existing icons original work or based on third-party artwork? Are there Heartbit colors, logos, or design guidelines to use?

Recommendation: reuse artwork whose rights can be established and prepare simple listing graphics with an easily replaceable working title. The inspected SVG files contained no attribution or source metadata; that absence does not establish ownership.

## Q21. macOS compatibility

Which macOS versions can the publisher test personally or through another tester?

The development machine reported macOS 27.0 during the 2026-09-30 inspection. The existing macOS 13+ claim is unverified.

Recommendation: distinguish the build's minimum target from versions actually tested, and make publication claims match the evidence. No supported minimum macOS version has been agreed in the interview.

## Q22. Live testing and Marketplace processing

Can the publisher arrange a disposable Teams meeting with a second participant or device, plus an installation test in a fresh macOS user account or another Mac? Can the publisher later upload an unpublished candidate and provide Elgato's processed package for testing?

Recommendation: the agent prepares test procedures and diagnostics; the publisher handles account actions and confirms what the second participant sees. Leave tests must cover attendee and organizer roles. This question does not authorize operating controls in an ordinary meeting.

## Q23. Required meeting situations

Must the first release work with Teams in the background, minimized, and while screen sharing?

Recommendation: require those common situations. Treat specialized cases such as multiple simultaneous meetings as unsupported initially, with safe failure when the target is ambiguous. These scope boundaries have not yet been accepted.

## Q24. Automatic-state acceptance

Is updating microphone, camera, and hand indicators within two seconds acceptable as a target during ordinary operation?

Recommendation: use that target and show explicit unknown or unavailable state when reliable state cannot be obtained. An active reaction wave may delay refresh because the single-operation lock must be preserved. Automatic updates are agreed; the two-second target and this delay allowance are not yet agreed.

## Q25. Remaining feature scope

Are the current nine actions, bounded reaction repeats, and automatic state updates the complete first-release scope? Should Leave retain its current single-press behavior?

Recommendation: retain that behavior, keep Blur excluded and keyboard fallbacks disabled, and add no further features unless the publisher identifies a must-have. The nine actions are Like, Love, Applause, Laugh, Surprise, Mute, Camera, Raise Hand, and Leave Call.

## Q26. Implementation handoff and timing

How should the completed work be delivered, and is there a deadline?

Recommendation: a dedicated branch and draft pull request containing code, tests, documentation, packaging changes, and publication materials. This workflow has not been authorized by an answer to this question. Final naming and paid signing remain deferred; the publisher will handle Marketplace submission and public release.

## After the answers

Update the publication plan and confirm the complete implementation scope. Research or draft a license matching the settled permissions; if no standard license fits, identify the proposed text as a draft rather than silently relaxing or broadening the policy. Keep unresolved rights, final naming, signing, and qualification steps explicit in the eventual handoff.
