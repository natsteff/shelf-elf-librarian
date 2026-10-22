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
                    topic("Run Magic when wanted", "Enable Magic in Profile Settings to display Run Magic and the enabled indicator. It runs only on selected visible files when clicked. Review its evidence and alternative interpretations. Remembering corrections is optional; only successful approved operations supply learning examples. Embedded media tags are not read.")
                    topic("Preview and file into the library", "Set a destination root and output masks in Profile Settings. Preview Renames reviews renames in the current folders. Preview Filing reviews Copy or Move destinations before Apply. File only keeps current filenames while folder masks still determine subfolders. Examine the full destinations and any blocked rows before applying.")
                    topic("Configure patterns and classifications", "Profile Settings → Workspace Filename Patterns & Filing Types defines ordered input patterns. The first enabled full-basename match wins. Type, System or Genre can select output folder/filename masks. Test examples or selected files before saving. Existing profiles retain compatibility parsing; suggested editable rules start disabled until reviewed. Unknown captured classifications require review before filing.")
                    topic("Undo, backups and folder cleanup", "Use a row’s undo arrow for its last direct rename, or History for journaled actions. Undo checks for conflicts or external changes and may refuse an unsafe reversal. Tools contains Clean Folder Names and settings export/import. Import confirms replacement and backs up settings first. Replacing the app with an older version does not undo file operations.")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8).textSelection(.enabled)
            }
            Divider()
            HStack { Link("Project on GitHub", destination: URL(string: "https://github.com/natsteff/shelf-elf-librarian")!); Spacer(); Button("Done", action: close).keyboardShortcut(.cancelAction) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
