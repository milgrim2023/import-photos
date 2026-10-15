import Foundation

/// What the always-visible bottom bar shows. Views render this; they decide nothing themselves.
struct BottomBarPresentation: Equatable {
    enum Mode: Equatable { case idle, running }

    let selectedItemCount: Int
    let canImport: Bool
    let isRunning: Bool
    var isCancelling = false
    let fractionCompleted: Double
    let currentFile: String

    var mode: Mode { isRunning ? .running : .idle }
    var importEnabled: Bool { canImport && !isRunning }
    var showsCancel: Bool { isRunning }
    var cancelEnabled: Bool { isRunning && !isCancelling }
    var cancelTitle: String { isCancelling ? "Cancelling…" : "Cancel" }
    var percentText: String { "\(Int((fractionCompleted * 100).rounded()))%" }
    var summary: String {
        selectedItemCount == 0
            ? "Select files or folders to import"
            : "\(selectedItemCount) item\(selectedItemCount == 1 ? "" : "s") selected"
    }
}

/// Everything the Results Sheet shows, derived from an `ImportReport`.
struct ResultsPresentation: Equatable {
    struct Stat: Equatable { let title: String; let value: Int; var isProblem = false }
    struct Row: Equatable { let primary: String; let secondary: String? }
    struct Section: Equatable { let title: String; let rows: [Row] }

    let title: String
    let stats: [Stat]
    let sidecarNote: String?
    let ignoredNote: String?
    let cancelledNote: String?
    let sections: [Section]

    init(report: ImportReport) {
        title = report.wasCancelled ? "Import Cancelled"
            : report.failedCount == 0 ? "Import Complete" : "Import Finished with Problems"

        var stats = [Stat(title: "Photos imported", value: report.importedCount),
                     Stat(title: "Skipped (duplicates)", value: report.skippedCount),
                     Stat(title: "Renamed", value: report.renamedCount)]
        if report.failedCount > 0 { stats.append(Stat(title: "Failed", value: report.failedCount, isProblem: true)) }
        self.stats = stats

        func plural(_ n: Int) -> String { n == 1 ? "file" : "files" }
        sidecarNote = report.sidecarCount == 0 ? nil
            : "\(report.sidecarCount) sidecar \(plural(report.sidecarCount)) (.xmp etc.) copied with their photos."
        let ignored = report.ignoredSidecars.count
        ignoredNote = ignored == 0 ? nil
            : "\(ignored) sidecar \(plural(ignored)) had no photo and \(ignored == 1 ? "was" : "were") ignored."

        let notImported = report.cancelledCount
        cancelledNote = notImported == 0 ? nil
            : "\(notImported) photo\(notImported == 1 ? " was" : "s were") not imported because the import was cancelled."

        var sections: [Section] = []
        if !report.failed.isEmpty {
            sections.append(Section(title: "Failed", rows: report.failed.map { Row(primary: $0.source.lastPathComponent, secondary: $0.reason) }))
        }
        if !report.skipped.isEmpty {
            sections.append(Section(title: "Skipped", rows: report.skipped.map { Row(primary: $0.source.lastPathComponent, secondary: nil) }))
        }
        if !report.ignoredSidecars.isEmpty {
            sections.append(Section(title: "Ignored sidecars (no photo)", rows: report.ignoredSidecars.map { Row(primary: $0.lastPathComponent, secondary: nil) }))
        }
        if !report.renamed.isEmpty {
            sections.append(Section(title: "Renamed", rows: report.renamed.map {
                Row(primary: "\($0.source.lastPathComponent) → \($0.new.lastPathComponent)", secondary: nil) }))
        }
        self.sections = sections
    }
}
