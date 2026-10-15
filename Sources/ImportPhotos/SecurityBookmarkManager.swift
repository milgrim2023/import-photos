import Foundation

public class RealSecurityBookmarkManager: SecurityBookmarkManager {
    private let defaults = UserDefaults.standard

    public init() {}

    public func saveBookmark(for url: URL, key: String) throws {
        defaults.set(try makeBookmark(url), forKey: "bookmark_\(key)")
    }

    public func loadBookmark(for key: String) -> URL? {
        guard let data = defaults.data(forKey: "bookmark_\(key)") else { return nil }
        return resolve(data) { try? self.saveBookmark(for: $0, key: key) }
    }

    public func saveBookmarks(for urls: [URL], key: String) throws {
        defaults.set(try urls.map(makeBookmark), forKey: "bookmarks_\(key)")
    }

    public func loadBookmarks(for key: String) -> [URL] {
        let list = defaults.array(forKey: "bookmarks_\(key)") as? [Data] ?? []
        return list.compactMap { resolve($0, refresh: { _ in }) }
    }

    private func makeBookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolve(_ data: Data, refresh: (URL) -> Void) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        // Sandbox: restored bookmark URLs only work after this call (held for app lifetime).
        _ = url.startAccessingSecurityScopedResource()
        if isStale { refresh(url) }
        return url
    }
}
