import SwiftUI

struct AboutShelfElfView: View {
    let close: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            BrandImage(name: "In-App-Logo").frame(width: 270, height: 270)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            Text(AppIdentity.version).font(.callout)
            if AppEnvironment.isFreshInstallTest { Text("Fresh Install Test · separate settings and history").font(.caption).foregroundStyle(.secondary) }
            Link("Shelf Elf Librarian on GitHub", destination: URL(string: "https://github.com/natsteff/shelf-elf-librarian")!)
            Spacer(minLength: 0)
            HStack { Spacer(); Button("Done", action: close).keyboardShortcut(.cancelAction) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct ShelfElfHelpView: View {
    let close: () -> Void
    private func topic(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(text).fixedSize(horizontal: false, vertical: true) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Using Shelf Elf Librarian").font(.title2.bold())
            Text("Clean filenames first, then file them into your library.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topic("Open a workspace", "Choose a library profile, then Open Workspace to select the files you want to organize. Include subfolders controls discovery. Refresh reloads files and ordinary cleanup proposals; it does not run Magic. Profile extensions filter which files are eligible.")
                    topic("Select and review files", "Click a current filename, type/size, filing indicator or unused row area to review one file. Use checkboxes for multiple files. The filename filter changes visible results; actions exclude hidden selections. Clear the filter with its × button.")
                    topic("Edit and rename", "The upper line is the current filename; the input below is the proposed name without its preserved extension. Edit the proposal and press Return or click its save button to rename immediately. The row checkmark applies a proposal immediately; Rename Selected applies selected visible proposals. Escape cancels an unsubmitted edit. Successful direct renames are deselected.")
                    topic("Understand differences and spelling", "Red marks removed/replaced source characters; blue marks proposed additions/replacements. Amber source underlines indicate unrecognized words. Open Show changes for details and Suggestions, or right-click an underlined word. Spelling replacements change the proposal only until Rename. Names may intentionally be absent from the dictionary; add preferred spelling/case exceptions in General Settings.")
                    topic("Edit filename components", "The inspector edits selected visible files. Bulk changes to Series or Season update proposals while preserving each file’s other components. Mixed values remain unchanged unless replaced. Confirm Filename Components is separate from immediate row renames and is used by reviewed preview operations. Use the extra component disclosure sections when a file needs a different interpretation.")
                    topic("Inspect embedded metadata", "A tag icon beside a filename and View Embedded Metadata in Filename Components open the same read-only details. Amber means tag values differ from components; other tags may simply add information. MP3 tags never alter components or proposed names. Edit those yourself when appropriate. MP4, M4V and MOV metadata can fill missing components needed by masks; existing values and manual edits take priority. Unsupported formats and read errors are explained in the popup. Refresh after external tag edits. No tags are written or purged.")
                    topic("Run Magic when wanted", "Enable Magic in Profile Settings to display Run Magic and the enabled indicator. It runs only on selected visible files when clicked. It analyzes and then asks you to confirm Copy or Move to Library using proposed filenames. The operation defaults to the bottom dropdown. Nothing is copied or moved before confirmation. Remembering corrections is optional; only successful approved operations supply learning examples. MP3 tags are reference information only; video metadata can fill missing components used by output masks. Tags are never written or removed.")
                    topic("Route mixed videos with Media Categories", "In Profile Settings → Build names & folders, enable Media Categories and map each category to an existing root-level library folder or a name to create on Apply. Six editable starters are provided: Commercials, Documentaries, Home Videos, Movies, Music Videos and TV Shows. Add your own categories and matching rules. Explicit selection/capture wins; specific Type + keyword rules precede keyword-only and Type-only rules. Set a default or require review. Category layouts build subfolders beneath the mapped folder. Nothing is routed by guessing existing folder names.")
                    topic("Preview and file into the library", "Set a destination root and output masks in Profile Settings. Preview Copy to Library or Preview Move to Library shows proposed filenames and destinations before Apply. Skip Individual Review & Copy/Move All preserves current filenames and asks for one confirmation; folder masks still determine subfolders. Blocked files remain excluded. Workspace renames use Rename Selected or row checkmarks.")
                    topic("Configure patterns and classifications", "Profile Settings → Workspace Filename Patterns & Filing Types defines ordered input patterns. The first enabled full-basename match wins. Type, System or Genre can select output folder/filename masks. Test examples or selected files before saving. Existing profiles retain compatibility parsing; suggested editable rules start disabled until reviewed. Unknown captured classifications require review before filing.")
                    topic("Undo, backups and folder cleanup", "Use a row’s undo arrow for its last direct rename, or History for journaled actions. Undo checks for conflicts or external changes and may refuse an unsafe reversal. Tools contains Clean Folder Names and settings export/import. Import confirms replacement and backs up settings first. Replacing the app with an older version does not undo file operations.")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8).textSelection(.enabled)
            }
            Divider()
            HStack { Link("Project on GitHub", destination: URL(string: "https://github.com/natsteff/shelf-elf-librarian")!); Spacer(); Button("Done", action: close).keyboardShortcut(.cancelAction) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
