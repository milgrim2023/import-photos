import Foundation

public class RealIngestionEngine: IngestionEngine {
    private let metadataProvider: MediaMetadataProvider
    private let pathTemplater: PathTemplater
    private let collisionJudge: CollisionJudge
    private let mediaTransferrer: MediaTransferrer

    public init(
        metadataProvider: MediaMetadataProvider,
        pathTemplater: PathTemplater,
        collisionJudge: CollisionJudge,
        mediaTransferrer: MediaTransferrer
    ) {
        self.metadataProvider = metadataProvider
        self.pathTemplater = pathTemplater
        self.collisionJudge = collisionJudge
        self.mediaTransferrer = mediaTransferrer
    }

    public func process(sources: [URL], destination: URL, template: String, timeOffset: TimeInterval, progress: @escaping @Sendable (ImportProgress) -> Void) async throws -> [TransferResult] {
        var results: [TransferResult] = []
        let destinationIndex = DestinationIndex(root: destination)
        let sidecarIndex = SidecarIndex()

        let expanded = expand(sources)
        let (files, pairedSidecars, pickedOrphans) = pairExplicitSidecars(expanded.files)
        let orphanSidecars = (expanded.orphans + pickedOrphans).sorted { $0.path < $1.path }

        for (index, fileURL) in files.enumerated() {
            // Cancel between files only: the file in flight always finishes (media + sidecars move together).
            if Task.isCancelled { results.append(.cancelled(source: fileURL)); continue }
            progress(ImportProgress(completed: index, total: files.count, currentFile: fileURL.lastPathComponent))
            do {
                // Unstructured task = shield: a cancel of the whole import never reaches the file in flight
                // (it would abort e.g. a video's metadata read and misfile it). We just stop before the next one.
                let paired = pairedSidecars[fileURL] ?? []
                results.append(try await Task {
                    try await self.importOne(fileURL, destination: destination, template: template, timeOffset: timeOffset,
                                             index: destinationIndex, sidecarIndex: sidecarIndex, paired: paired)
                }.value)
            } catch {
                // One bad file must not stop the rest of the card.
                results.append(.failed(source: fileURL, reason: error.localizedDescription))
            }
        }

        results.append(contentsOf: orphanSidecars.map { .ignoredSidecar(source: $0) })   // noted, never imported
        progress(ImportProgress(completed: files.count, total: files.count, currentFile: ""))
        return results
    }

    private func importOne(
        _ fileURL: URL, destination: URL, template: String, timeOffset: TimeInterval,
        index: DestinationIndex, sidecarIndex: SidecarIndex, paired: [URL]
    ) async throws -> TransferResult {
        var metadata = try await metadataProvider.fetchMetadata(for: fileURL)

        // Offset is applied before both path calculation and the duplicate check.
        metadata = MediaMetadata(name: metadata.name, size: metadata.size,
                                 timestamp: metadata.timestamp.addingTimeInterval(timeOffset))
        let targetURL = destination.appendingPathComponent(pathTemplater.calculateRelativePath(from: metadata, template: template))

        // Only destination files sharing the name can be duplicates, so only those are read.
        let candidates = try await index.metadata(named: metadata.name, excluding: fileURL, using: metadataProvider)

        switch collisionJudge.evaluate(incoming: metadata, destinationFiles: candidates) {
        case .skip:
            return .skipped(source: fileURL, reason: "Duplicate found")
        case .new:
            let finalURL = availableURL(for: targetURL)
            let sidecars = unique(sidecarIndex.sidecars(of: fileURL) + paired)
            let copied = try await mediaTransferrer.transfer(source: fileURL, to: finalURL, sidecars: sidecars)
            index.recordImported(metadata)
            return finalURL == targetURL
                ? .success(source: fileURL, destination: finalURL, sidecars: copied)
                : .renamed(source: fileURL, original: targetURL, new: finalURL, sidecars: copied)
        }
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }   // same file via /tmp vs /private/tmp
    }

    private func availableURL(for target: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: target.path) else { return target }
        let dir = target.deletingLastPathComponent()
        let ext = target.pathExtension
        let stem = target.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let name = ext.isEmpty ? "\(stem)_\(n)" : "\(stem)_\(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// A picked sidecar travels with its picked parent; it is not imported on its own. Needed in the
    /// sandbox, where picking individual files does not grant access to list their folder.
    private func pairExplicitSidecars(_ files: [URL]) -> (media: [URL], paired: [URL: [URL]], orphans: [URL]) {
        var mediaByKey: [String: URL] = [:]
        for f in files where !SidecarNaming.isSidecar(f) {
            for key in SidecarNaming.keys(forMedia: f) { mediaByKey[key] = f }
        }
        var paired: [URL: [URL]] = [:]
        var media: [URL] = []
        var orphans: [URL] = []
        for f in files {
            if SidecarNaming.isSidecar(f) {
                // Sidecars are never imported on their own: paired ones travel with their photo, orphans are reported.
                if let parent = mediaByKey[SidecarNaming.key(forSidecar: f)] { paired[parent, default: []].append(f) } else { orphans.append(f) }
            } else {
                media.append(f)
            }
        }
        return (media, paired, orphans)
    }

    /// Files pass through; directories expand recursively into photos only (hidden files and
    /// every sidecar are left out; sidecars are attached to their photo when it is imported).
    private func expand(_ sources: [URL]) -> (files: [URL], orphans: [URL]) {
        let fm = FileManager.default
        var seen = Set<URL>()
        var expanded: [URL] = []
        var orphans: [URL] = []
        func add(_ url: URL) { if seen.insert(url).inserted { expanded.append(url) } }

        for source in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { continue }
            guard isDir.boolValue else { add(source); continue }
            guard let enumerator = fm.enumerator(
                at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            var found: [URL] = []
            for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                found.append(url)
            }
            // Sidecars found in a folder are discovered per photo (SidecarIndex), never imported by themselves.
            // Names a photo's sidecar could carry, so the orphan check is O(1) per sidecar.
            var mediaKeys = Set<String>()
            for url in found where !SidecarNaming.isSidecar(url) { mediaKeys.formUnion(SidecarNaming.keys(forMedia: url)) }
            for url in found.sorted(by: { $0.path < $1.path }) {
                if !SidecarNaming.isSidecar(url) { add(url) }
                else if !mediaKeys.contains(SidecarNaming.key(forSidecar: url)) { orphans.append(url) }
            }
        }
        return (expanded, orphans)
    }

}

/// Finds `.xmp` siblings. Each folder is listed once, however many photos it holds.
private final class SidecarIndex: @unchecked Sendable {
    private var byFolder: [String: [String: [URL]]] = [:]   // folder path -> stem -> sidecars

    func sidecars(of media: URL) -> [URL] {
        let folder = media.deletingLastPathComponent()
        if byFolder[folder.path] == nil {
            var index: [String: [URL]] = [:]
            let siblings = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in siblings where SidecarNaming.isSidecar(url) {
                index[url.deletingPathExtension().lastPathComponent, default: []].append(url)
            }
            byFolder[folder.path] = index
        }
        let index = byFolder[folder.path] ?? [:]
        return (index[media.lastPathComponent] ?? []) + (index[media.deletingPathExtension().lastPathComponent] ?? [])
    }
}

/// Destination files by name. Names come from one cheap enumeration; metadata (EXIF etc.) is read
/// lazily, only for files whose name matches something being imported, and cached.
private final class DestinationIndex: @unchecked Sendable {
    private var urlsByName: [String: [URL]] = [:]
    private var metadataByPath: [String: MediaMetadata] = [:]
    private var imported: [String: [MediaMetadata]] = [:]

    init(root: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            urlsByName[url.lastPathComponent, default: []].append(url)
        }
    }

    /// `source` is skipped: when the source folder sits inside the destination, a file would
    /// otherwise match itself and be reported as its own duplicate.
    func metadata(named name: String, excluding source: URL, using provider: MediaMetadataProvider) async throws -> [MediaMetadata] {
        var result = imported[name] ?? []
        let sourcePath = source.resolvingSymlinksInPath().path
        for url in urlsByName[name] ?? [] where url.resolvingSymlinksInPath().path != sourcePath {
            if let cached = metadataByPath[url.path] { result.append(cached); continue }
            let fetched = try await provider.fetchMetadata(for: url)
            metadataByPath[url.path] = fetched
            result.append(fetched)
        }
        return result
    }

    func recordImported(_ metadata: MediaMetadata) {
        imported[metadata.name, default: []].append(metadata)
    }
}
