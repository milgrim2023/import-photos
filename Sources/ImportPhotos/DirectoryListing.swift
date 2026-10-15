import Foundation

public enum FileSortOrder: String, CaseIterable, Identifiable, Sendable {
    case dateOldestFirst = "Date (oldest first)"
    case dateNewestFirst = "Date (newest first)"
    case captureDateOldestFirst = "Capture date (oldest first)"
    case captureDateNewestFirst = "Capture date (newest first)"
    case name = "Name"
    public var id: String { rawValue }

    /// Capture-date orders need metadata read from the files (see `DashboardViewModel.loadCaptureDates`).
    public var usesCaptureDate: Bool { self == .captureDateOldestFirst || self == .captureDateNewestFirst }
}

enum DirectoryListing {
    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Folders first, then files in `order`. Hidden items omitted. Ties fall back to name.
    static func children(of directory: URL, order: FileSortOrder = .dateOldestFirst, captureDates: [URL: Date] = [:]) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return sorted(urls, order: order, captureDates: captureDates)
    }

    /// Folders first, then files in `order`. Ties fall back to name.
    /// `captureDates` is only consulted by the capture-date orders; files without one fall back to their file date.
    static func sorted(_ urls: [URL], order: FileSortOrder, captureDates: [URL: Date] = [:]) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        func info(_ u: URL) -> (isDir: Bool, date: Date) {
            let v = try? u.resourceValues(forKeys: keys)
            return (v?.isDirectory == true, v?.contentModificationDate ?? .distantPast)
        }
        let rows = urls.map { url -> (url: URL, info: (isDir: Bool, date: Date)) in
            var i = info(url)
            if order.usesCaptureDate, !i.isDir, let captured = captureDates[url] { i.date = captured }
            return (url, i)
        }
        func byName(_ a: URL, _ b: URL) -> Bool { a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending }
        return rows.sorted { l, r in
            if l.info.isDir != r.info.isDir { return l.info.isDir }
            if !l.info.isDir, l.info.date != r.info.date {
                switch order {
                case .dateOldestFirst, .captureDateOldestFirst: return l.info.date < r.info.date
                case .dateNewestFirst, .captureDateNewestFirst: return l.info.date > r.info.date
                case .name: break
                }
            }
            return byName(l.url, r.url)
        }.map(\.url)
    }
}
