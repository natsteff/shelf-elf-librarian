# License and notice maintenance

LICENSE contains the complete, unmodified AGPL-3.0 license copied from Nate's local Forge-GameSheets/LICENSE. Do not edit the standard license text or automatically replace its version. This project selects AGPL version 3, not an automatic later-version grant.

Legal/CORE-TERMS.txt is now an informational shared usage notice, not a EULA. Legal/SHELF-ELF-NOTES.txt describes this app's operations. Increment the Notice version when changing the notice. scripts/generate-terms.py generates both USAGE-NOTICE.md and the in-app text, including the full LICENSE. build.sh invokes it and packages the documents. README links both documents. No custom monetary cap or use-only restriction remains.

Continue stores acknowledgedUsageNoticeVersion, acknowledgedUsageNoticeAppRelease and usageNoticeAcknowledgedAt locally. The app release is short version plus build. A new release or notice prompts again; old EULA acceptance is intentionally not reused. Quit dismisses the sheet, then terminates after dismissal without recording acknowledgment. Do not describe acknowledgment as legally required acceptance of AGPL merely to run the program.

The standard license remains authoritative. The notice must not add restrictions to AGPL rights. Preserve third-party licensing obligations. Any future shared changes should be reviewed, versioned and distributed through app updates, not silently change the standard AGPL license or installed app terms.
