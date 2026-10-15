import Foundation

/// Post-import summary (PRD §3.4). `importedCount` counts photos, renamed ones included.
/// Sidecars are copied implicitly with their photo and only counted (`sidecarCount`).
public struct ImportReport: Equatable {
    public struct Skipped: Equatable { public let source: URL; public let reason: String }
    public struct Renamed: Equatable { public let source: URL; public let original: URL; public let new: URL }
    public struct Failed: Equatable { public let source: URL; public let reason: String }

    public let importedCount: Int
    public let sidecarCount: Int
    public let skipped: [Skipped]
    public let renamed: [Renamed]
    public let failed: [Failed]
    /// Sidecars that had no photo and were left behind.
    public let ignoredSidecars: [URL]
    /// Files never reached because the import was cancelled.
    public let cancelled: [URL]

    public var skippedCount: Int { skipped.count }
    public var renamedCount: Int { renamed.count }
    public var failedCount: Int { failed.count }
    public var cancelledCount: Int { cancelled.count }
    public var wasCancelled: Bool { !cancelled.isEmpty }

    public init(results: [TransferResult]) {
        var imported = 0, sidecars = 0
        var skipped: [Skipped] = [], renamed: [Renamed] = [], failed: [Failed] = [], ignored: [URL] = [], cancelled: [URL] = []
        for result in results {
            switch result {
            case let .success(_, _, copied):
                imported += 1
                sidecars += copied.count
            case let .skipped(source, reason):
                skipped.append(.init(source: source, reason: reason))
            case let .renamed(source, original, new, copied):
                imported += 1
                sidecars += copied.count
                renamed.append(.init(source: source, original: original, new: new))
            case let .failed(source, reason):
                failed.append(.init(source: source, reason: reason))
            case let .ignoredSidecar(source):
                ignored.append(source)
            case let .cancelled(source):
                cancelled.append(source)
            }
        }
        importedCount = imported
        sidecarCount = sidecars
        self.skipped = skipped
        self.renamed = renamed
        self.failed = failed
        ignoredSidecars = ignored
        self.cancelled = cancelled
    }
}
