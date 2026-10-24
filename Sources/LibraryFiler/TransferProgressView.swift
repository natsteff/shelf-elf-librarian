import SwiftUI
import FilerCore

/// Shared by reviewed filing, keep-current-names filing and Magic, for both Copy and Move.
struct TransferProgressView: View {
    @EnvironmentObject var m: Model
    let plan: Plan
    @State private var stopping = false
    private var action: String { plan.mode == .copy ? "Copy" : "Move" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(m.busy ? "\(action) in progress" : m.transferSummary ?? "\(action) stopped")
                .font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("Profile: " + plan.profile.name).font(.headline)
            Text("Library destination: " + plan.profile.root).textSelection(.enabled)
            if m.busy {
                ProgressView()
                Text(m.progress.isEmpty ? "Preparing transfer…" : m.progress)
                Text(stopping ? "Stopping after the current file. Completed files remain completed." : "Please wait while files are transferred and verified.")
                    .foregroundStyle(.secondary)
            } else {
                Label(m.transferDetails.isEmpty ? "Review operation history for per-file results." : "Some files or follow-up steps need attention. Review the details below and History & Recovery.",
                      systemImage: m.transferDetails.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                if !m.transferDetails.isEmpty {
                    ScrollView {
                        Text(m.transferDetails.joined(separator: "\n\n"))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                }
            }
            Spacer()
            HStack {
                if m.busy {
                    Button(stopping ? "Stopping…" : "Cancel Transfer") {
                        stopping = true; m.cancellation.cancel()
                    }.disabled(stopping)
                }
                Spacer()
                if !m.busy {
                    Button("Done") { m.dismissTransfer() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
