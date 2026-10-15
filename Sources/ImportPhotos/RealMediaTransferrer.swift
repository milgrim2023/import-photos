import Foundation

public class RealMediaTransferrer: MediaTransferrer {
    public init() {}

    /// Copies media + sidecars all-or-nothing: everything is staged under hidden `.partial`
    /// names, then moved into place. On any failure nothing is left in the destination.
    @discardableResult
    public func transfer(source: URL, to destination: URL, sidecars: [URL]) async throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        var plan: [(from: URL, final: URL)] = [(source, destination)]
        for sidecar in sidecars {
            // Sidecar takes the parent's final name so it stays paired after a rename.
            let wanted = SidecarNaming.destination(of: sidecar, source: source, destinationMedia: destination)
            // Existing sidecars always win: a RAW+JPEG pair shares one, and an older edited one must
            // never be replaced or shadowed by a newer copy from the card.
            if fm.fileExists(atPath: wanted.path) { continue }
            plan.append((sidecar, wanted))
        }

        var staged: [(partial: URL, final: URL)] = []
        var moved: [URL] = []
        do {
            for item in plan {
                let partial = item.final.deletingLastPathComponent()
                    .appendingPathComponent(".\(item.final.lastPathComponent).partial")
                try? fm.removeItem(at: partial)
                try fm.copyItem(at: item.from, to: partial)
                staged.append((partial, item.final))
            }
            for item in staged {
                try fm.moveItem(at: item.partial, to: item.final)
                moved.append(item.final)
            }
        } catch {
            for item in staged { try? fm.removeItem(at: item.partial) }
            for url in moved { try? fm.removeItem(at: url) }
            throw error
        }
        return plan.dropFirst().map(\.final).sorted { $0.path < $1.path }
    }
}
