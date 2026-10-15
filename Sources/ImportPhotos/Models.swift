import Foundation

public struct MediaMetadata: Equatable {
    public let name: String
    public let size: Int64
    public let timestamp: Date
}

public enum DeDuplicationDecision: Equatable {
    case new
    case skip
}

public enum TransferResult: Hashable {
    /// `sidecars` = destination URLs of the sidecar files copied implicitly with the photo.
    case success(source: URL, destination: URL, sidecars: [URL] = [])
    case skipped(source: URL, reason: String)
    case renamed(source: URL, original: URL, new: URL, sidecars: [URL] = [])
    case failed(source: URL, reason: String)
    /// A sidecar with no photo. Never imported; reported so the user knows it was left behind.
    case ignoredSidecar(source: URL)
    /// The import was cancelled before this file was reached; nothing was copied.
    case cancelled(source: URL)
}

public struct ImportProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let currentFile: String

    public init(completed: Int, total: Int, currentFile: String) {
        self.completed = completed
        self.total = total
        self.currentFile = currentFile
    }
}
