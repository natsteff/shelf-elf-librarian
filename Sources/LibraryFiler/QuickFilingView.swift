import SwiftUI
import FilerCore

/// The single execution confirmation for Magic and the explicit keep-current-names bypass.
struct QuickFilingView: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(m.quickKeepNames ? "Confirm Copy or Move — Keep Current Filenames" : "Confirm Copy or Move").font(.title2.bold())
            Picker("Operation", selection: $m.quickMode) {
                Text("Copy to Library").tag(Mode.copy)
                Text("Move to Library").tag(Mode.move)
            }.pickerStyle(.segmented).onChange(of: m.quickMode) { m.rebuildQuickFiling(m.quickMode) }
            Text(m.quickKeepNames ? "Individual component confirmation is skipped for this operation. Current filenames are preserved; folder masks still determine destinations." : "Individual component confirmation is skipped for this operation. Proposed filenames and the profile’s folder masks determine library destinations.")
            if let plan = m.quickPlan {
                Text("Library destination: " + plan.profile.root).textSelection(.enabled)
                let ready = plan.rows.filter(\.actionable).count
                let blocked = plan.rows.count - ready
                Text("\(ready) eligible • \(blocked) blocked • \(plan.rows.count) files in this operation").font(.headline)
                Text(plan.mode == .copy ? "Workspace originals remain unchanged. Library copies receive the names shown below." : "Eligible workspace files will be moved into the library with the names shown below.").font(.callout)
                GroupedPlanRows(plan: plan)
                Text("Only eligible files will be processed. Collisions, missing folder components and filesystem checks remain enforced. Cancellation may leave a partially completed operation; review History.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { m.showQuickFiling = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Confirm \(plan.mode == .copy ? "Copy" : "Move") \(ready) Files") { m.applyQuickFiling() }
                        .buttonStyle(.borderedProminent).disabled(ready == 0)
                }
            } else {
                if m.busy { ProgressView("Checking destinations…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    Text(m.quickFailure ?? "Unable to prepare this operation. Return to the workspace and preview again.").foregroundStyle(.orange).textSelection(.enabled)
                    Spacer()
                    Button("Back to Workspace") { m.showQuickFiling = false }.keyboardShortcut(.cancelAction)
                }
            }
        }.disabled(m.busy).padding(20).frame(width: 930, height: 700)
    }
}
