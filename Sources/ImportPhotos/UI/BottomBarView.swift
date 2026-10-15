import SwiftUI

/// Always-visible bottom bar. Idle: selection summary + Import. Running: progress + current file.
struct BottomBarView: View {
    let dashboard: DashboardViewModel
    let importer: ImportViewModel

    var body: some View {
        let bar = BottomBarPresentation(
            selectedItemCount: dashboard.selectedItemCount, canImport: dashboard.canImport,
            isRunning: importer.isRunning, isCancelling: importer.isCancelling, fractionCompleted: importer.fractionCompleted, currentFile: importer.currentFile)
        HStack(spacing: 12) {
            switch bar.mode {
            case .running:
                ProgressView(value: bar.fractionCompleted).accessibilityIdentifier("progress-bar")
                Text(bar.percentText).monospacedDigit().frame(width: 44, alignment: .trailing)
                    .accessibilityIdentifier("progress-percent")
                Text(bar.currentFile).lineLimit(1).truncationMode(.middle).frame(width: 260, alignment: .leading)
                    .accessibilityIdentifier("progress-file")
                Button(bar.cancelTitle) { importer.cancel() }
                    .disabled(!bar.cancelEnabled)
                    .accessibilityIdentifier("cancel-button")
            case .idle:
                Text(bar.summary).foregroundStyle(.secondary).accessibilityIdentifier("selection-summary")
                Spacer()
                Button("Import") { importer.beginImport(using: dashboard) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!bar.importEnabled)
                    .accessibilityIdentifier("import-button")
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
        .frame(height: 48)
        .background(.bar)
    }
}
