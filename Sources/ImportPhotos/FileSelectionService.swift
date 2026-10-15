import Foundation
import AppKit

@MainActor
public class RealFileSelectionService: FileSelectionService {
    private let bookmarkManager: SecurityBookmarkManager
    private let sourcesKey = "selected_sources"
    private let destinationKey = "selected_destination"

    public init(bookmarkManager: SecurityBookmarkManager) {
        self.bookmarkManager = bookmarkManager
    }

    public func selectSources() async throws -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Select Source"
        panel.message = "Choose a folder to browse, or pick individual photos and folders."

        return try await withCheckedThrowingContinuation { continuation in
            panel.begin { response in
                if response == .OK, !panel.urls.isEmpty {
                    continuation.resume(returning: panel.urls)
                } else {
                    continuation.resume(throwing: NSError(domain: "FileSelection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selection cancelled"]))
                }
            }
        }
    }

    public func selectDestination() async throws -> URL {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Destination"

        return try await withCheckedThrowingContinuation { continuation in
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "FileSelection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selection cancelled"]))
                }
            }
        }
    }

    public func persistSelection(sources: [URL]?, destination: URL?) async throws {
        if let sources {
            try bookmarkManager.saveBookmarks(for: sources, key: sourcesKey)
        }
        if let destination {
            try bookmarkManager.saveBookmark(for: destination, key: destinationKey)
        }
    }

    public func loadLastSelection() async -> (sources: [URL], destination: URL?) {
        (bookmarkManager.loadBookmarks(for: sourcesKey), bookmarkManager.loadBookmark(for: destinationKey))
    }
}
