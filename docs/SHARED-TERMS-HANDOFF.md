# Codex handoff: AGPL license and shared usage notice

License approach introduced in Shelf Elf Librarian Build 23; current app Build 59, usage notice 2.0. This replaces the previous custom EULA approach. Nate selected AGPL-3.0 to match his other projects. Nate confirmed the Build 23 startup notice works after launching the updated app.

## Instruction for a receiving assistant

Inspect your project's existing license, startup and storage first. Use the standard AGPL-3.0 license and a separate informational usage notice, not an additional restrictive EULA. Confirm the project's existing version-3-only versus or-later choice; do not silently change it. Wait for explicit implementation authorization from Nate. Feedback and questions are discussion, not automatic instructions to edit. Do not message other chats without authorization.

## Actual reusable files

Reference repository: https://github.com/natsteff/shelf-elf-librarian

- LICENSE: actual complete, unmodified AGPL-3.0 text, included at the repository root.
- Legal/CORE-TERMS.txt: actual shared informational notice, version 2.0. Despite its legacy filename, this is no longer contractual EULA wording.
- Legal/SHELF-ELF-NOTES.txt: actual app-specific behavior and project/support URL. Replace with your app's details.
- USAGE-NOTICE.md: generated complete notice for repository/GitHub readers.
- Sources/LibraryFiler/LicenseTerms.swift: full displayed notice/license plus SwiftUI view. Generated text; edit source documents instead.
- Sources/LibraryFiler/App.swift: startup, acknowledgment state, menu access and quit sequencing.
- scripts/generate-terms.py and scripts/build.sh: generate matching repository/app documents and package the sources.
- README.md and Legal/MAINTENANCE.md: publication and maintenance details.

This handoff references the actual documents; it does NOT embed the full license. Agents without access to these paths need copies of LICENSE, the Legal documents and reference implementation. The remote https://github.com/natsteff/shelf-elf-librarian is private; do not assume local changes are pushed. Nothing has been published as part of this work.

## Licensing correction: do not reuse the old EULA

The previous use-only grant, redistribution prohibition and custom US $50 liability cap were removed. Do not copy those provisions into other projects. AGPL is the license and includes its standard warranty and liability provisions (sections 15–17). No payment, refund or compensation promise is added. No disclaimer can override mandatory law.

AGPL section 9 does not require accepting the license merely to receive or run the program. The startup notice is informational and must not impose new restrictions on copying, modification, redistribution or other license rights. Use License & Usage Notice, Continue and Quit; do not call Continue agreement to a new contract. The full AGPL remains unmodified and authoritative. App-specific backup/operation details are guidance, not extra license conditions.

## Migration checklist: back out the old EULA implementation

1. Remove the custom EULA's use-only grant, redistribution restrictions, custom monetary liability cap, contract-acceptance language and any backend contract gate introduced solely for that EULA. Preserve unrelated account, permission and operational safety checks. Do not reset profiles, files, history, authentication or other settings.
2. Install the complete, unmodified AGPL-3.0 text as root LICENSE, matching the project's version-3-only or or-later grant. For Shelf Elf, the selected grant is version 3 only. Keep applicable copyright and third-party notices. Do not replace an existing different license without authority from its rights holders.
3. Replace EULA.md with USAGE-NOTICE.md. Keep a short explanation of backups, previews, file operations and recovery limits as informational guidance. Include no extra restrictions on AGPL rights. Link LICENSE and USAGE-NOTICE.md from README; remove obsolete EULA links.
4. Replace the old shared-core EULA wording and app-specific supplement. Shelf Elf's Legal/CORE-TERMS.txt now contains the actual replacement notice despite the legacy filename. Copy that current file, not an earlier version. Tailor SHELF-ELF-NOTES.txt to the receiving app.
5. Rename License & Terms to License & Usage Notice, Agree & Continue to Continue, and Decline & Quit to Quit (use Leave or Return for web apps). Later viewing has Done. Continue records a notice acknowledgment, not acceptance of an additional contract. Keep the full license readily readable.
6. Separate acknowledgment from prior EULA acceptance. Shelf Elf replaced acceptedLicenseTermsVersion, acceptedLicenseAppRelease and licenseTermsAcceptedAt with acknowledgedUsageNoticeVersion, acknowledgedUsageNoticeAppRelease and usageNoticeAcknowledgedAt. Do not map old acceptance into the new values: users should see the corrected notice once. Old unused keys can remain inert; deleting all application preferences is unnecessary.
7. Prompt when the current notice identity or stable app version/build differs from the acknowledged values. Shelf Elf uses notice 2.0 and Build 23. Continue saves the new values and timestamp. Quit saves nothing. New builds prompt again; repeated launches of the same acknowledged build do not. Display changes and full-license access must not make the AGPL text itself editable.
8. Preserve the sheet-dismissal-before-quit fix below. Generate displayed and repository documents from one source, package them with the release, and update build scripts so they no longer regenerate the obsolete EULA.
9. Update maintenance instructions and any earlier Codex handoffs so no agent reinstates the restrictive EULA, $50 cap or legally required contract acceptance. Describe any old manual test results as historical; verify the new app locally.
10. Verify: fresh acknowledgment state presents the notice; Quit exits/leaves and prompts again next visit; Continue suppresses it for that same release; a new release/notice prompts again; menu access shows both documents; existing app data remains intact. Prepare locally and do not push or message other agents unless Nate authorizes it.

## Desktop behavior

Show a calm startup License & Usage Notice with a short introduction, scrollable/selectable notice and a Read Full AGPL-3.0 License button. Allow switching back to the usage notice. The menu permanently offers License & Usage Notice… with Done for later reading.

Show the startup notice once per new application version/build OR changed notice version. Use stable CFBundleShortVersionString + ':' + CFBundleVersion, never process start time. Continue records acknowledgment locally; Quit does not. Repeat launches of the same acknowledged release do not prompt. Old EULA acceptance intentionally does not suppress the new notice.

Shelf Elf uses acknowledgedUsageNoticeVersion, acknowledgedUsageNoticeAppRelease and usageNoticeAcknowledgedAt in app-local preferences. These are convenience records, not legal audit evidence. Do not share acknowledgment across unrelated apps. Clearing preferences prompts again. The initial sheet prevents accidental dismissal, but does not claim legal acceptance is required to run AGPL software.

## Quit bug and fix

Originally NSApplication.shared.terminate(nil) was called directly from the attached required SwiftUI sheet. It beeped and failed to quit.

The Quit button now invokes a parent callback: set quitAfterTermsDismissal = true, then showTerms = false. In sheet(isPresented:onDismiss:), check that flag and dispatch termination on DispatchQueue.main.async. Never record acknowledgment along the quit path. The read-only Done action only dismisses.

Nate manually verified the earlier Build 22 version of this sequencing: decline quit successfully; next launch after declining prompted again; acceptance suppressed the notice on repeated openings of that same release. Build 23 retains the fix and changes the meaning/labels to notice acknowledgment. Nate subsequently confirmed that the updated startup presentation works. Verify behavior on each receiving platform.

## Repository requirement

Include complete root LICENSE and USAGE-NOTICE.md linked from README. Generate app and repository notice copies from the same sources. Include them in distribution/source packaging. EULA.md has been removed; do not create a contradictory license. Preserve third-party notices. Prepare changes locally unless publishing is authorized.

## Web / Docker considerations

A browser cannot reliably close a user-opened tab. Use Leave or Return instead of promising to quit a container; acknowledgment is a UI preference, not an extra AGPL license condition. Keep license/notice accessible. Do not invent an additional legal authorization gate on backend APIs for ordinary use.

With accounts, store per-app, per-user notice acknowledgment using stable notice/release IDs and timestamp. Without accounts, persistent browser storage is an option, with repetition after clearing storage or changing browsers. Do not assume an administrator acknowledges for all users. Bake a stable release ID into images: container restarts or changing container IDs must not prompt again; new deployed releases should prompt at next visit per Nate's preference. Tailor the usage notice to actual app operations.

## Proposed App-Standards repository — not yet created

A separate shared standards repository is a future option; it is not a runtime dependency.

Suggested contents: unmodified license references with provenance; shared informational notices and version/hash; per-app supplement templates; behavior/usage-notice.md; adapters/macos-swiftui and adapters/web; consumer manifests with pinned shared versions; proposals, changelog and AGENTS.md collaboration instructions.

Use Git/PRs as shared memory. Each consuming repo needs AGENTS.md instructions to consult the shared contract and its pinned version. Shared repositories do not automatically grant access, notify running agents or authorize messaging. Remote agents need access or a source bundle. Do not store user files, secrets or acknowledgment records there.

There is no external upstream provider or update feed today. AGPL version 3 is a published fixed license, not a frequently changing EULA subscription. A newer license version must not automatically relicense projects. Record provenance/licensing for any future externally sourced guidance.

For shared notice or behavior updates: propose a reviewed change, publish a versioned immutable release with hash, then have CI/bot open update PRs for every registered consumer. Track adoption/failures, review supplements, and release through each app's normal process. Updated desktop installs or Docker deployments receive new content; existing installations cannot be updated merely by editing a repository. Review first, rather than silently altering legal documents. No shared repo, scheduled watcher, CI fan-out or cross-project messaging has been configured here.
