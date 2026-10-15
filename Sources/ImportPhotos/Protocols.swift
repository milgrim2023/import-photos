import Foundation

public protocol MediaMetadataProvider {
    func fetchMetadata(for url: URL) async throws -> MediaMetadata
}

public protocol PathTemplater {
    func calculateRelativePath(from metadata: MediaMetadata, template: String) -> String
}

public protocol CollisionJudge {
    func evaluate(incoming: MediaMetadata, destinationFiles: [MediaMetadata]) -> DeDuplicationDecision
}

public protocol MediaTransferrer {
    /// Copies the file and its sidecars all-or-nothing. A sidecar already present at the destination is
    /// left untouched (never replaced, never duplicated). Returns the destination URLs of sidecars written.
    @discardableResult
    func transfer(source: URL, to destination: URL, sidecars: [URL]) async throws -> [URL]
}

public protocol IngestionEngine {
    func process(
        sources: [URL],
        destination: URL,
        template: String,
        timeOffset: TimeInterval,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> [TransferResult]
}

public extension IngestionEngine {
    func process(sources: [URL], destination: URL, template: String, timeOffset: TimeInterval) async throws -> [TransferResult] {
        try await process(sources: sources, destination: destination, template: template, timeOffset: timeOffset, progress: { _ in })
    }
}

public protocol SecurityBookmarkManager {
    func saveBookmark(for url: URL, key: String) throws
    func loadBookmark(for key: String) -> URL?
    func saveBookmarks(for urls: [URL], key: String) throws
    func loadBookmarks(for key: String) -> [URL]
}

public protocol FileSelectionService {
    /// Files and/or folders. Throws if the user cancels.
    func selectSources() async throws -> [URL]
    func selectDestination() async throws -> URL
    func persistSelection(sources: [URL]?, destination: URL?) async throws
    func loadLastSelection() async -> (sources: [URL], destination: URL?)
}
