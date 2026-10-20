# Validation scope

The current local app is **0.1.0 Alpha (Build 13)**, compiled for arm64 and locally ad hoc signed. The latest build completed with zero failures across 15 fixture scenarios. Screenshots are deferred during early development; recent settings and workspace-restoration changes are awaiting user review.

## Reproduce

Run `./scripts/build.sh`. It builds and runs `SafetyChecks` against disposable temporary fixtures, packages the app, and verifies its local signature. The runner invokes the production planner, executor, journal and undo coordinator. It does not require XCTest.

The scenarios cover:

- Copy payload/source preservation and explicit guarded copy undo.
- Same-volume move, occupied-original refusal and guarded move undo.
- The independently forced verified-copy move branch.
- Injected verification/publication failures retaining source/recovery information.
- Journal reopening, existing/late destination conflicts, duplicate batch outputs and no-op.
- Stale sources, replaced destination roots, links/dangling links and path traversal.
- Cancellation between files and externally changed undo targets.
- Profile eligibility, missing/unconfirmed interpretation fields, chapter grouping and shared destinations.
- Unexpected new destination folders, music/video output paths and extension-case preservation.

These checks are not a release-safety certification. They do not cover actual unplugged/network volumes, disk-full/read-only hardware failures, all concurrent filesystem races, or metadata fidelity across differing filesystems. The verified-copy move branch is forced on local fixtures rather than tested on an actual second volume. See the README limitations.
