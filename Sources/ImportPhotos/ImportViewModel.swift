import Foundation
import Observation

@MainActor
@Observable
public final class ImportViewModel {
    public private(set) var isRunning = false
    public private(set) var isCancelling = false
    public private(set) var report: ImportReport?

    public private(set) var currentFile = ""
    public private(set) var fractionCompleted: Double = 0

    public var errorMessage: String?

    private let engine: IngestionEngine
    private var runTask: Task<Void, Never>?

    public init(engine: IngestionEngine) {
        self.engine = engine
    }

    public func start(sources: [URL], destination: URL, template: String, timeOffset: TimeInterval) async {
        isRunning = true
        report = nil
        defer { isRunning = false; isCancelling = false }
        errorMessage = nil
        do {
            let results = try await engine.process(
                sources: sources, destination: destination, template: template, timeOffset: timeOffset,
                progress: { [weak self] p in Task { @MainActor in self?.apply(p) } })
            report = ImportReport(results: results)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts an import that can be cancelled with `cancel()`. Ignored while one is already running.
    public func beginImport(using dashboard: DashboardViewModel) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.start(using: dashboard)
            self?.runTask = nil
        }
    }

    /// Asks the running import to stop after the file it is on. Everything already imported is kept.
    public func cancel() {
        guard isRunning, let runTask else { return }
        isCancelling = true
        runTask.cancel()
    }

    /// Imports what the dashboard currently describes (selection, destination, template, offset).
    public func start(using dashboard: DashboardViewModel) async {
        guard let destination = dashboard.destinationURL else { return }
        await start(sources: dashboard.importSources, destination: destination,
                    template: dashboard.template, timeOffset: dashboard.timeOffset)
    }

    private func apply(_ p: ImportProgress) {
        currentFile = p.currentFile
        fractionCompleted = p.total == 0 ? 0 : Double(p.completed) / Double(p.total)
    }
}
