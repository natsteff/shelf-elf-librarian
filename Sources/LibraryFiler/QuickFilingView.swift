import SwiftUI
import FilerCore

/// The single execution confirmation for Magic and the explicit keep-current-names bypass.
struct QuickFilingView: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let transfer = m.transferPlan {
                TransferProgressView(plan: transfer)
            } else {
            Text(m.quickIsMagic ? "Confirm Run Magic" : m.quickKeepNames ? "Confirm Copy or Move — Keep Current Filenames" : "Confirm Copy or Move").font(.title2.bold())
            if m.quickIsMagic {
                Label("Review this Magic run before continuing. It will apply proposed filenames and the Copy/Move action below. Confirm only if these files, settings and destinations are correct.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Operation", selection: $m.quickMode) {
                Text("Copy to Library").tag(Mode.copy)
                Text("Move to Library").tag(Mode.move)
            }.pickerStyle(.radioGroup).horizontalRadioGroupLayout().disabled(m.busy).onChange(of: m.quickMode) { m.rebuildQuickFiling(m.quickMode) }
            Text(m.quickKeepNames ? "Individual component confirmation is skipped for this operation. Current filenames are preserved; folder masks still determine destinations." : "Individual component confirmation is skipped for this operation. Proposed filenames and the profile’s folder masks determine library destinations.")
            if let plan = m.quickPlan {
                Text("Profile: " + plan.profile.name).font(.headline)
                Text("Library destination: " + plan.profile.root).textSelection(.enabled)
                if plan.magicRun == true && plan.profile.kind == .music {
                    Text("MP3 tag update: " + (plan.profile.magicUpdateMP3Tags == true ? "On — use nonempty components" : "Off") + " • MP3 purge: " + (plan.profile.magicPurgeMP3Tags == true ? "On — use profile keep list" : "Off")).font(.headline)
                    if plan.profile.magicPurgeMP3Tags == true {
                        Text("Keep: " + MP3KeepTag.allCases.filter { (plan.profile.mp3TagsToKeep ?? Set(MP3KeepTag.allCases)).contains($0) }.map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                    if plan.profile.magicUpdateMP3Tags == true || plan.profile.magicPurgeMP3Tags == true {
                        Text("Order: prepare components → update MP3 tags → purge unchecked tags → publish Copy/Move. Disabled steps are skipped. Other file types are filed without tag changes. MP3 tag changes have no Undo or retained backup.").font(.callout).foregroundStyle(.orange)
                    }
                }
                let ready = plan.rows.filter(\.actionable).count
                let blocked = plan.rows.count - ready
                Text("\(ready) eligible • \(blocked) blocked • \(plan.rows.count) files in this operation").font(.headline)
                Text(plan.mode == .copy ? "Workspace originals remain unchanged. Library copies receive the names shown below." : "Eligible workspace files will be moved into the library with the names shown below.").font(.callout)
                GroupedPlanRows(plan: plan)
                Text("Only eligible files will be processed. Collisions, missing folder components and filesystem checks remain enforced. Cancellation may leave a partially completed operation; review History.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { m.cancelQuickFiling() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(plan.magicRun == true ? "Run Magic & \(plan.mode == .copy ? "Copy" : "Move") \(ready) Files" : "\(plan.mode == .copy ? "Copy" : "Move") \(ready) Files") { m.applyQuickFiling() }
                        .buttonStyle(.borderedProminent).disabled(ready == 0 || m.busy)
                }
            } else {
                if m.busy {
                    ProgressView("Checking destinations and MP3 steps…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button("Cancel") { m.cancelQuickFiling() }.keyboardShortcut(.cancelAction)
                }
                else {
                    Text(m.quickFailure ?? "Unable to prepare this operation. Return to the workspace and preview again.").foregroundStyle(.orange).textSelection(.enabled)
                    Spacer()
                    Button("Back to Workspace") { m.showQuickFiling = false }.keyboardShortcut(.cancelAction)
                }
            }
            }
        }.padding(20).frame(width: 930, height: 700)
        .interactiveDismissDisabled(m.transferPlan != nil)
    }
}
