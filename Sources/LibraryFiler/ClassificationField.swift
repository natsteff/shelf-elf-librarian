import SwiftUI
import FilerCore

struct ClassificationField: View {
    @EnvironmentObject var m: Model
    @State private var adding = false
    @State private var name = ""
    private var key: String { PatternEngine.classificationKey(m.active) }
    private var types: [FilingType] { m.active.classifications ?? [] }
    private var value: String {
        guard !m.visibleSelected.isEmpty else { return "" }
        let values = Set(m.visibleSelected.map { FieldCatalog.get(key, $0.fields) })
        return values.count == 1 ? values.first! : "@mixed"
    }
    var body: some View {
        if m.active.kind == .video || m.active.kind == .roms || m.active.kind == .music || !types.isEmpty || m.visibleSelected.contains(where: { !FieldCatalog.get(key, $0.fields).isEmpty }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(key).font(.caption.bold()).foregroundStyle(.secondary)
                Picker(key, selection: Binding(get: { value }, set: { value in
                    if value == "@add" { name = ""; adding = true }
                    else if value != "@mixed" { m.updateFields { FieldCatalog.set(key, value, &$0) } }
                })) {
                    if value == "@mixed" { Text("Mixed values — choose to replace").tag("@mixed") }
                    Text("Unspecified").tag("")
                    if !value.isEmpty && value != "@mixed" && !types.contains(where: { $0.name == value }) { Text(value + " (unconfigured)").tag(value) }
                    ForEach(types) { entry in Text(entry.name).tag(entry.name) }
                    Text("Add Type…").tag("@add")
                }.labelsHidden().disabled(m.visibleSelected.isEmpty)
            }
            .alert("Add " + key, isPresented: $adding) {
                TextField("Name", text: $name)
                Button("Add") { do { try m.addFilingType(name); m.updateFields { FieldCatalog.set(key, name.trimmingCharacters(in: .whitespacesAndNewlines), &$0) } } catch { m.error = error.localizedDescription } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Adds a classification to this profile and assigns it to selected visible files. It inherits the profile's output masks; edit mappings in Profile Settings.") }
        }
    }
}
extension Model {
    func addFilingType(_ input: String) throws {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines); try component(name)
        guard let index = profiles.firstIndex(where: { $0.id == activeID }) else { throw fail("Save a profile first.") }
        guard PatternEngine.lookup(name, profile: active) == nil else { throw fail("That classification or alias already exists.") }
        var next = profiles
        next[index].classifications = (next[index].classifications ?? []) + [FilingType(name)]
        try PatternEngine.validate(next[index])
        try JSONEncoder().encode(next).write(to: support.appendingPathComponent("profiles.json"), options: .atomic)
        profiles = next; invalidate()
    }
}
