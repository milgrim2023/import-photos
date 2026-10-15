import SwiftUI

/// Modal summary of a finished import. All wording comes from `ResultsPresentation`.
struct ResultsSheet: View {
    let report: ImportReport
    let dismiss: () -> Void

    var body: some View {
        let results = ResultsPresentation(report: report)
        VStack(alignment: .leading, spacing: 12) {
            Text(results.title).font(.title2.bold()).accessibilityIdentifier("results-title")
            HStack(spacing: 24) {
                ForEach(results.stats, id: \.title) { stat in
                    VStack(alignment: .leading) {
                        Text("\(stat.value)").font(.largeTitle.monospacedDigit()).foregroundStyle(stat.isProblem ? Color.red : .primary)
                        Text(stat.title).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stat.value) \(stat.title)")
                    .accessibilityIdentifier("stat-\(stat.title)")
                }
            }
            if let note = results.cancelledNote {
                Label(note, systemImage: "xmark.octagon").font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("cancelled-note")
            }
            if let note = results.sidecarNote {
                Label(note, systemImage: "paperclip").font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sidecar-note")
            }
            if let note = results.ignoredNote {
                Label(note, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("ignored-note")
            }
            List {
                ForEach(results.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.rows.indices, id: \.self) { i in
                            let row = section.rows[i]
                            if let secondary = row.secondary {
                                VStack(alignment: .leading) {
                                    Text(row.primary)
                                    Text(secondary).font(.caption).foregroundStyle(.red)
                                }
                            } else {
                                Text(row.primary)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction).accessibilityIdentifier("results-done")
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 380)
    }
}
