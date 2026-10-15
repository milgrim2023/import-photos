import SwiftUI

/// Single-screen dashboard: source browser | settings, bottom bar (import / progress).
public struct RootView: View {
    @State private var dashboard: DashboardViewModel
    @State private var importer: ImportViewModel
    @State private var showResults = false

    public init(dashboard: DashboardViewModel, importer: ImportViewModel) {
        _dashboard = State(initialValue: dashboard)
        _importer = State(initialValue: importer)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SourceBrowserView(dashboard: dashboard)
                Divider()
                SettingsPanel(dashboard: dashboard)
            }
            if let warning = dashboard.sidecarWarning {
                Divider()
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .accessibilityIdentifier("sidecar-warning")
            }
            Divider()
            BottomBarView(dashboard: dashboard, importer: importer)
        }
        .frame(minWidth: 900, minHeight: 680)
        .task { await dashboard.restoreLastSelection() }
        .task(id: PreviewInputs(selection: dashboard.selection, amount: dashboard.offsetAmount,
                                unit: dashboard.offsetUnit, template: dashboard.template)) {
            await dashboard.updatePreview()
        }
        .task(id: CaptureLoadInputs(sort: dashboard.sortOrder, folder: dashboard.currentFolder, roots: dashboard.sourceRoots)) {
            await dashboard.loadCaptureDates()
        }
        .onChange(of: importer.report) { _, report in showResults = report != nil }
        .alert("Import Failed", isPresented: Binding(get: { importer.errorMessage != nil }, set: { if !$0 { importer.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(importer.errorMessage ?? "") }
        .sheet(isPresented: $showResults) {
            if let report = importer.report { ResultsSheet(report: report) { showResults = false } }
        }
    }
}

private struct PreviewInputs: Hashable {
    let selection: Set<URL>
    let amount: Int
    let unit: DashboardViewModel.OffsetUnit
    let template: String
}

private struct CaptureLoadInputs: Hashable {
    let sort: FileSortOrder
    let folder: URL?
    let roots: [URL]
}
