# Public screenshots

Use the dedicated isolated **Screenshot Demo** edition, never the owner's production profiles or workspace. Build first, then run `./scripts/build-screenshot-demo.sh` to create fictional filename-only fixtures and a starter-profile settings archive beneath `/private/tmp/Shelf Elf Demo`.

The demo app loads `Demo Settings.json` and opens `Workspace/Music` automatically, with `Library/Music` as its destination. Its own profile, preference and journal store is `com.local.LibraryFiler.ScreenshotDemo`, separate from both production and Fresh Install Test. The opt-in fixture path exists only in the separately copied/signed demo bundle; never upload that demo bundle as a release app. The music artists/titles and video examples are fictional text placeholders with media extensions, not playable media. No personal library data, settings exports or real filenames belong in screenshots.

Capture the current public version label, a populated workspace with components, and a library preview using only these fixtures. Review every image for personal filenames, home paths, unrelated windows, menus and hover help. Use actual unaltered app screenshots; identify the isolated demo edition in captions. Never copy staged production paths into fixture files or commit generated settings archives.

Beta 1 screenshot filenames: `docs/images/beta1-workspace.jpg` and `docs/images/beta1-copy-preview.jpg`.
