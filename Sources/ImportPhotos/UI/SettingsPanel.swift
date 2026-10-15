import SwiftUI

/// Right panel: destination, template, time offset.
struct SettingsPanel: View {
    @Bindable var dashboard: DashboardViewModel

    var body: some View {
        Form {
            Section("Destination") {
                Text(dashboard.destinationLabel)
                    .foregroundStyle(dashboard.destinationURL == nil ? .secondary : .primary)
                    .lineLimit(2).truncationMode(.middle)
                    .accessibilityIdentifier("destination-label")
                Button("Choose…") { Task { await dashboard.chooseDestination() } }
                    .accessibilityIdentifier("choose-destination")
            }
            Section("Template") {
                TextField("Template", text: $dashboard.template).labelsHidden().accessibilityIdentifier("template-field")
                Text("{{YEAR}} {{MONTH}} {{DAY}} {{HOUR}} {{MINUTE}} {{SECOND}} {{NAME}}")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Time Offset") {
                HStack {
                    Stepper(value: $dashboard.offsetAmount, in: -999...999) {
                        Text(dashboard.offsetLabel).monospacedDigit().accessibilityIdentifier("offset-label")
                    }
                    .accessibilityIdentifier("offset-stepper")
                    Picker("Unit", selection: $dashboard.offsetUnit) {
                        ForEach(DashboardViewModel.OffsetUnit.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .labelsHidden().frame(width: 100).accessibilityIdentifier("offset-unit")
                }
                HStack {
                    Button("−1 h") { dashboard.offsetAmount = -1; dashboard.offsetUnit = .hours }.accessibilityIdentifier("offset-minus-1h")
                    Button("+1 h") { dashboard.offsetAmount = 1; dashboard.offsetUnit = .hours }.accessibilityIdentifier("offset-plus-1h")
                    Button("Reset") { dashboard.offsetAmount = 0 }
                        .disabled(dashboard.offsetAmount == 0)
                        .accessibilityIdentifier("offset-reset")
                }
                .controlSize(.small)
            }
            Section("Preview") { previewView }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var previewView: some View {
        if let p = dashboard.preview {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.fileName).font(.headline).lineLimit(1).accessibilityIdentifier("preview-file")
                row("Camera time", p.originalTimestamp.formatted(date: .abbreviated, time: .standard), id: "preview-camera-time")
                row("Corrected", p.adjustedTimestamp.formatted(date: .abbreviated, time: .standard), id: "preview-corrected-time")
                row("Saved as", p.adjustedPath, id: "preview-saved-as")
            }
            .font(.callout)
        } else {
            Text("Select a photo to preview where it will be saved.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle).accessibilityIdentifier(id)
        }
    }
}
