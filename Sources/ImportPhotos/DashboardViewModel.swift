import Foundation
import Observation

@MainActor
@Observable
public final class DashboardViewModel {
    /// What the user picked in the system panel: one folder to browse, or several files/folders.
    public private(set) var sourceRoots: [URL] = []
    public private(set) var destinationURL: URL?

    public static let defaultTemplate = "{{YEAR}}/{{MONTH}}/{{NAME}}"
    private static let templateKey = "template"

    public var template: String {
        didSet { defaults.set(template, forKey: Self.templateKey) }
    }

    public enum OffsetUnit: String, CaseIterable, Identifiable, Sendable {
        case minutes, hours, days
        public var id: String { rawValue }
        var seconds: TimeInterval {
            switch self { case .minutes: 60; case .hours: 3600; case .days: 86_400 }
        }
    }

    /// Camera-clock correction. Deliberately not persisted: it belongs to one card/trip.
    public var offsetAmount: Int = 0
    public var offsetUnit: OffsetUnit = .hours

    /// "+2", "0", "-3": what the offset stepper shows.
    public var offsetLabel: String { offsetAmount > 0 ? "+\(offsetAmount)" : "\(offsetAmount)" }

    public var destinationLabel: String { destinationURL?.path ?? "None chosen" }

    /// Header of the browser: the folder being shown, or a label for hand-picked items.
    public var browserTitle: String { currentFolder?.path ?? "Selected items" }

    /// Quick Look needs a selected file (folders can't be previewed).
    public var canPreview: Bool { items.contains { selection.contains($0) && !DirectoryListing.isDirectory($0) } }

    /// Seconds added to each file's timestamp.
    public var timeOffset: TimeInterval { Double(offsetAmount) * offsetUnit.seconds }

    /// Rows selected in the source browser. A selected folder imports recursively.
    public var selection: Set<URL> = []

    /// What the engine should import: the selected rows (minus anything inside another selected
    /// folder), plus picked sidecars belonging to selected photos. Sidecars are never selected by hand.
    public var importSources: [URL] {
        let all = selection.sorted { $0.path < $1.path }
        let top = all.filter { url in
            !all.contains { other in other != url && url.path.hasPrefix(other.path + "/") }
        }
        let wanted = Set(top.flatMap(SidecarNaming.keys(forMedia:)))
        let pickedSidecars = sourceRoots.filter { SidecarNaming.isSidecar($0) && wanted.contains(SidecarNaming.key(forSidecar: $0)) }
        return top + pickedSidecars
    }

    public var selectedItemCount: Int { importSources.filter { !SidecarNaming.isSidecar($0) }.count }

    // MARK: Browsing

    public var sortOrder: FileSortOrder = .dateOldestFirst

    /// Folder currently shown in the grid; nil = the picked items themselves.
    public private(set) var currentFolder: URL?

    /// A single picked folder is the browsing "top"; with several picks, the picks are the top.
    private var topFolder: URL? {
        sourceRoots.count == 1 && DirectoryListing.isDirectory(sourceRoots[0]) ? sourceRoots[0] : nil
    }

    /// What the grid shows right now.
    public var items: [URL] {
        let all = currentFolder.map { DirectoryListing.children(of: $0, order: sortOrder, captureDates: captureDates) }
            ?? DirectoryListing.sorted(sourceRoots, order: sortOrder, captureDates: captureDates)
        return all.filter { !SidecarNaming.isSidecar($0) }   // sidecars travel with their photo; never shown
    }

    public var canGoUp: Bool { currentFolder != nil && !Self.samePlace(currentFolder, topFolder) }

    private static func samePlace(_ a: URL?, _ b: URL?) -> Bool { a?.standardizedFileURL.path == b?.standardizedFileURL.path }

    public func open(_ folder: URL) {
        guard DirectoryListing.isDirectory(folder) else { return }
        currentFolder = folder
    }

    public func goUp() {
        guard let current = currentFolder, canGoUp else { return }
        currentFolder = sourceRoots.contains { Self.samePlace($0, current) } ? nil : current.deletingLastPathComponent()
    }

    // MARK: Sidecar warning

    /// Sandbox: picking individual photos grants access to those files only, so their `.xmp`
    /// sidecars can't be found unless picked too. Photos inside a browsed folder are fine.
    public var sidecarWarning: String? {
        let picked = sourceRoots.filter { !DirectoryListing.isDirectory($0) }
        let pickedSidecarKeys = Set(picked.filter(SidecarNaming.isSidecar).map(SidecarNaming.key(forSidecar:)))
        let exposed = importSources.filter { url in
            picked.contains(url)
                && !SidecarNaming.isSidecar(url)
                && pickedSidecarKeys.isDisjoint(with: SidecarNaming.keys(forMedia: url))
                && !canListFolder(url.deletingLastPathComponent())
        }
        guard !exposed.isEmpty else { return nil }
        let n = exposed.count
        return "\(n) photo\(n == 1 ? "" : "s") picked without sidecar files. Any .xmp next to "
            + "\(n == 1 ? "it" : "them") can't be found: pick the sidecars too, or pick the folder instead."
    }

    // MARK: Capture-date sorting

    /// EXIF/video capture dates, read lazily and cached for the session. Until a file's date arrives the
    /// grid orders it by file date, so choosing the sort never blocks the UI.
    public private(set) var captureDates: [URL: Date] = [:]
    public private(set) var isLoadingCaptureDates = false

    /// Reads capture dates for the files now shown (once each, a few at a time, in chunks so the grid
    /// re-sorts progressively). Does nothing unless a capture-date sort is selected. Call it again after
    /// the sort, folder or sources change; cancelling the calling task stops it cleanly.
    public func loadCaptureDates() async {
        guard sortOrder.usesCaptureDate else { return }
        let pending = items.filter { !DirectoryListing.isDirectory($0) && captureDates[$0] == nil }
        guard !pending.isEmpty else { return }
        isLoadingCaptureDates = true
        defer { isLoadingCaptureDates = false }

        let provider = metadataProvider
        let chunkSize = 48, parallelism = 8
        for start in stride(from: 0, to: pending.count, by: chunkSize) {
            if Task.isCancelled { return }
            let chunk = Array(pending[start..<min(start + chunkSize, pending.count)])
            let found = await withTaskGroup(of: (URL, Date?).self) { group -> [(URL, Date?)] in
                var next = chunk.makeIterator(), out: [(URL, Date?)] = []
                func addNext() { if let url = next.next() { group.addTask { (url, try? await provider.fetchMetadata(for: url).timestamp) } } }
                for _ in 0..<parallelism { addNext() }
                while let result = await group.next() { out.append(result); addNext() }
                return out
            }
            for (url, date) in found {
                if let date { captureDates[url] = date }
                else if !Task.isCancelled {   // unreadable: remember the file date so we don't retry forever
                    captureDates[url] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                }
            }
        }
    }

    // MARK: Quick Look

    /// Bound to the Quick Look panel; non-nil while previewing.
    public var previewURL: URL?

    /// Files in the folder being shown; Quick Look lets the user step through these.
    public var previewableFiles: [URL] { items.filter { !DirectoryListing.isDirectory($0) } }

    public func requestPreview() {
        previewURL = items.first { selection.contains($0) && !DirectoryListing.isDirectory($0) }
    }

    // MARK: Click selection (Finder semantics)

    public enum ClickMode { case replace, toggle, extend }

    private var anchor: URL?

    public func click(_ url: URL, mode: ClickMode) {
        switch mode {
        case .replace:
            selection = [url]
            anchor = url
        case .toggle:
            if !selection.insert(url).inserted { selection.remove(url) }
            anchor = url
        case .extend:
            let shown = items
            guard let from = anchor.flatMap({ a in shown.firstIndex { Self.samePlace($0, a) } }),
                  let to = shown.firstIndex(where: { Self.samePlace($0, url) }) else { return click(url, mode: .replace) }
            selection = Set(shown[min(from, to)...max(from, to)])
        }
    }

    public func selectAll() { selection = Set(items) }
    public func clearSelection() { selection = []; anchor = nil }

    public var canImport: Bool {
        !sourceRoots.isEmpty && destinationURL != nil && !selection.isEmpty
            && !template.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public struct OffsetPreview: Equatable {
        public let fileName: String
        public let originalTimestamp: Date
        public let adjustedTimestamp: Date
        public let originalPath: String
        public let adjustedPath: String
    }

    /// What the offset + template do to the first selected file. Call `updatePreview()` after any input changes.
    public private(set) var preview: OffsetPreview?

    public func updatePreview() async {
        guard let file = firstSelectedFile(),
              let metadata = try? await metadataProvider.fetchMetadata(for: file) else { preview = nil; return }
        let adjusted = MediaMetadata(name: metadata.name, size: metadata.size,
                                     timestamp: metadata.timestamp.addingTimeInterval(timeOffset))
        preview = OffsetPreview(
            fileName: metadata.name,
            originalTimestamp: metadata.timestamp,
            adjustedTimestamp: adjusted.timestamp,
            originalPath: pathTemplater.calculateRelativePath(from: metadata, template: template),
            adjustedPath: pathTemplater.calculateRelativePath(from: adjusted, template: template))
    }

    private func firstSelectedFile() -> URL? {
        for url in importSources where !SidecarNaming.isSidecar(url) {
            if !DirectoryListing.isDirectory(url) { return url }
            let files = (FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])?
                .compactMap { $0 as? URL } ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.path < $1.path }
            if let first = files.first { return first }
        }
        return nil
    }

    private let fileSelection: FileSelectionService
    private let metadataProvider: MediaMetadataProvider
    private let pathTemplater: PathTemplater
    private let defaults: UserDefaults
    private let canListFolder: (URL) -> Bool

    public init(
        fileSelection: FileSelectionService,
        metadataProvider: MediaMetadataProvider = RealMediaMetadataProvider(),
        pathTemplater: PathTemplater = RealPathTemplater(),
        defaults: UserDefaults = .standard,
        canListFolder: @escaping (URL) -> Bool = { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil }
    ) {
        self.canListFolder = canListFolder
        self.fileSelection = fileSelection
        self.metadataProvider = metadataProvider
        self.pathTemplater = pathTemplater
        self.defaults = defaults
        self.template = defaults.string(forKey: Self.templateKey) ?? Self.defaultTemplate
    }

    public func chooseSources() async {
        guard let urls = try? await fileSelection.selectSources() else { return }  // cancelled
        sourceRoots = urls
        currentFolder = topFolder
        // Picking a single folder = "browse this". Picking files / several items = "import these".
        let browsesSingleFolder = urls.count == 1 && DirectoryListing.isDirectory(urls[0])
        selection = browsesSingleFolder ? [] : Set(urls.filter { !SidecarNaming.isSidecar($0) })
        try? await fileSelection.persistSelection(sources: urls, destination: nil)
    }

    public func chooseDestination() async {
        guard let url = try? await fileSelection.selectDestination() else { return }
        destinationURL = url
        try? await fileSelection.persistSelection(sources: nil, destination: url)
    }

    public func restoreLastSelection() async {
        let last = await fileSelection.loadLastSelection()
        sourceRoots = last.sources
        currentFolder = topFolder
        destinationURL = last.destination
    }
}
