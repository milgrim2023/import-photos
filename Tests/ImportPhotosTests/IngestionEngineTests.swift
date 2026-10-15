import XCTest
@testable import ImportPhotos

final class IngestionDeDuplicationTests: XCTestCase {

    func testSkipsFileAlreadyInDestinationWhenOffsetAdjustedTimestampMatches() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let offset: TimeInterval = 3600
        // Destination copy was imported earlier with its timestamp already corrected (+1h).
        try fx.write("same-bytes", to: fx.destination.appendingPathComponent("photo.jpg"), modified: t0.addingTimeInterval(offset))
        let incoming = try fx.write("same-bytes", to: fx.source.appendingPathComponent("photo.jpg"), modified: t0)

        let results = try await fx.makeEngine().process(
            sources: [incoming], destination: fx.destination, template: "{{NAME}}", timeOffset: offset)

        XCTAssertEqual(results, [.skipped(source: incoming, reason: "Duplicate found")])
    }
}

final class IngestionRenameTests: XCTestCase {

    func testCollidingDifferentFileIsImportedWithNumberedSuffix() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let existing = try fx.write("old-content", to: fx.destination.appendingPathComponent("IMG_0001.JPG"), modified: t0)
        let incoming = try fx.write("different-content", to: fx.source.appendingPathComponent("IMG_0001.JPG"), modified: t0.addingTimeInterval(60))

        let results = try await fx.makeEngine().process(
            sources: [incoming], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        let renamed = fx.destination.appendingPathComponent("IMG_0001_1.JPG")
        XCTAssertEqual(results, [.renamed(source: incoming, original: existing, new: renamed)])
        XCTAssertEqual(try String(contentsOf: renamed), "different-content")
        XCTAssertEqual(try String(contentsOf: existing), "old-content")
    }
}

final class IngestionSidecarTests: XCTestCase {

    func testXmpSidecarIsImportedAlongsideItsParent() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let raw = try fx.write("raw-bytes", to: fx.source.appendingPathComponent("IMG_0001.CR2"), modified: t0)
        try fx.write("<xmp/>", to: fx.source.appendingPathComponent("IMG_0001.xmp"), modified: t0)

        _ = try await fx.makeEngine().process(
            sources: [raw], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(try String(contentsOf: fx.destination.appendingPathComponent("IMG_0001.xmp")), "<xmp/>")
    }

    func testSidecarFollowsParentsRenamedStem() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        try fx.write("old-raw", to: fx.destination.appendingPathComponent("IMG_0001.CR2"), modified: t0)
        let raw = try fx.write("new-raw", to: fx.source.appendingPathComponent("IMG_0001.CR2"), modified: t0.addingTimeInterval(60))
        try fx.write("<xmp/>", to: fx.source.appendingPathComponent("IMG_0001.xmp"), modified: t0)

        _ = try await fx.makeEngine().process(
            sources: [raw], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(try String(contentsOf: fx.destination.appendingPathComponent("IMG_0001_1.xmp")), "<xmp/>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fx.destination.appendingPathComponent("IMG_0001.xmp").path))
    }

    func testExplicitlyPickedSidecarPairsWithItsParentInsteadOfImportingStandalone() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let raw = try fx.write("raw", to: fx.source.appendingPathComponent("IMG_0001.CR2"), modified: t0)
        let xmp = try fx.write("<xmp/>", to: fx.source.appendingPathComponent("IMG_0001.xmp"), modified: t0)

        let results = try await fx.makeEngine().process(
            sources: [raw, xmp], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [.success(source: raw, destination: fx.destination.appendingPathComponent("IMG_0001.CR2"),
                                          sidecars: [fx.destination.appendingPathComponent("IMG_0001.xmp")])])
        XCTAssertEqual(try String(contentsOf: fx.destination.appendingPathComponent("IMG_0001.xmp")), "<xmp/>")
    }
}

final class IngestionSelectionTests: XCTestCase {

    func testDirectorySourceIsExpandedRecursivelyWithoutImportingSidecarsStandalone() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("DCIM/100/A.JPG"), modified: t0)
        let b = try fx.write("b", to: fx.source.appendingPathComponent("DCIM/101/sub/B.CR2"), modified: t0)
        try fx.write("<xmp/>", to: fx.source.appendingPathComponent("DCIM/101/sub/B.xmp"), modified: t0)

        let results = try await fx.makeEngine().process(
            sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(Set(results), [
            .success(source: a, destination: fx.destination.appendingPathComponent("A.JPG")),
            .success(source: b, destination: fx.destination.appendingPathComponent("B.CR2"),
                     sidecars: [fx.destination.appendingPathComponent("B.xmp")]),
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fx.destination.appendingPathComponent("B.xmp").path))
    }
}

final class IngestionProgressTests: XCTestCase {

    func testReportsCurrentFileAndCompletedCountThenFinalEvent() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let b = try fx.write("b", to: fx.source.appendingPathComponent("B.JPG"), modified: t0)
        let log = ProgressLog()

        _ = try await fx.makeEngine().process(
            sources: [a, b], destination: fx.destination, template: "{{NAME}}", timeOffset: 0,
            progress: { log.record($0) })

        XCTAssertEqual(log.events, [
            ImportProgress(completed: 0, total: 2, currentFile: "A.JPG"),
            ImportProgress(completed: 1, total: 2, currentFile: "B.JPG"),
            ImportProgress(completed: 2, total: 2, currentFile: ""),
        ])
    }
}

final class IngestionAtomicityTests: XCTestCase {

    func testFailedTransferLeavesNoPartialFilesInDestination() async throws {
        let fx = try Fixture()
        defer {
            // Restore perms so cleanup can delete.
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                ofItemAtPath: fx.source.appendingPathComponent("IMG_0001.xmp").path)
            fx.cleanUp()
        }
        let raw = try fx.write("raw", to: fx.source.appendingPathComponent("IMG_0001.CR2"), modified: t0)
        let xmp = try fx.write("<xmp/>", to: fx.source.appendingPathComponent("IMG_0001.xmp"), modified: t0)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: xmp.path)

        let results = try await fx.makeEngine().process(
            sources: [raw], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)
        guard case .failed = results.first else { return XCTFail("expected a per-file failure, got \(results)") }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fx.destination.path)
        XCTAssertEqual(leftovers, [])
    }
}

final class IngestionTimeOffsetTests: XCTestCase {

    func testOffsetMovesFileIntoNextMonthsFolder() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        var c = DateComponents(); c.year = 2023; c.month = 10; c.day = 31; c.hour = 23; c.minute = 30
        let lateOctober = Calendar.current.date(from: c)!
        let incoming = try fx.write("x", to: fx.source.appendingPathComponent("P.JPG"), modified: lateOctober)

        let results = try await fx.makeEngine().process(
            sources: [incoming], destination: fx.destination, template: "{{YEAR}}/{{MONTH}}/{{NAME}}", timeOffset: 3600)

        XCTAssertEqual(results, [.success(source: incoming, destination: fx.destination.appendingPathComponent("2023/11/P.JPG"))])
    }
}

final class IngestionScalingTests: XCTestCase {

    /// Overhead per file must not grow with folder size (a 1,500-photo card folder took ~15 s before).
    func testLargeFolderWithSidecarsImportsInSeconds() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let folder = fx.source.appendingPathComponent("DCIM/100CANON")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<1500 {
            let name = String(format: "IMG_%04d", i)
            try Data("raw".utf8).write(to: folder.appendingPathComponent("\(name).CR2"))
            try Data("<xmp/>".utf8).write(to: folder.appendingPathComponent("\(name).xmp"))
        }

        let started = Date()
        let results = try await fx.makeEngine().process(
            sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(results.count, 1500)
        XCTAssertLessThan(elapsed, 5, "took \(elapsed)s")
    }
}

/// Cameras like the Ricoh GR name sidecars after the full file name: `R0001173.DNG.xmp`.
final class IngestionFullNameSidecarTests: XCTestCase {

    func testFullNameSidecarTravelsWithItsParentEvenWhenItsOwnDateDiffers() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        var c = DateComponents(); c.year = 2025; c.month = 6; c.day = 18; c.hour = 12
        var c2 = DateComponents(); c2.year = 2026; c2.month = 1; c2.day = 20; c2.hour = 12
        let dng = try fx.write("raw", to: fx.source.appendingPathComponent("R0001173.DNG"), modified: Calendar.current.date(from: c)!)
        try fx.write("<xmp/>", to: fx.source.appendingPathComponent("R0001173.DNG.xmp"), modified: Calendar.current.date(from: c2)!)

        let results = try await fx.makeEngine().process(
            sources: [fx.source], destination: fx.destination, template: "{{YEAR}}/{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [.success(source: dng, destination: fx.destination.appendingPathComponent("2025/R0001173.DNG"),
                                          sidecars: [fx.destination.appendingPathComponent("2025/R0001173.DNG.xmp")])])
        XCTAssertEqual(try String(contentsOf: fx.destination.appendingPathComponent("2025/R0001173.DNG.xmp")), "<xmp/>")
    }

    func testFullNameSidecarFollowsARenamedParent() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        try fx.write("old", to: fx.destination.appendingPathComponent("R1.DNG"), modified: t0)
        let dng = try fx.write("new", to: fx.source.appendingPathComponent("R1.DNG"), modified: t0.addingTimeInterval(60))
        try fx.write("<xmp/>", to: fx.source.appendingPathComponent("R1.DNG.xmp"), modified: t0)

        _ = try await fx.makeEngine().process(sources: [dng], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(try String(contentsOf: fx.destination.appendingPathComponent("R1_1.DNG.xmp")), "<xmp/>")
    }

    func testExplicitlyPickedFullNameSidecarPairsWithItsParent() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let dng = try fx.write("raw", to: fx.source.appendingPathComponent("R1.DNG"), modified: t0)
        let xmp = try fx.write("<xmp/>", to: fx.source.appendingPathComponent("R1.DNG.xmp"), modified: t0)

        let results = try await fx.makeEngine().process(sources: [dng, xmp], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results.count, 1)
    }
}

/// RAW+JPEG shooters (e.g. Sony ARW+JPG) often have ONE `DSC00001.xmp` shared by both files.
final class IngestionSharedSidecarTests: XCTestCase {

    func testRawPlusJpegSharingOneSidecarBothImportAndTheSidecarIsCopiedOnce() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let folder = fx.source.appendingPathComponent("DCIM/100MSDCF")
        try fx.write("raw", to: folder.appendingPathComponent("DSC00001.ARW"), modified: t0)
        try fx.write("jpg", to: folder.appendingPathComponent("DSC00001.JPG"), modified: t0)
        try fx.write("<xmp/>", to: folder.appendingPathComponent("DSC00001.xmp"), modified: t0)

        let results = try await fx.makeEngine().process(
            sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results.count, 2)
        let saved = try FileManager.default.contentsOfDirectory(atPath: fx.destination.path).sorted()
        XCTAssertEqual(saved, ["DSC00001.ARW", "DSC00001.JPG", "DSC00001.xmp"])
    }

    /// A sidecar already in the target is never replaced, and no second copy of a (newer) one is added.
    func testSidecarAlreadyAtDestinationIsLeftAloneAndNothingElseIsWritten() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        try fx.write("<edited-earlier/>", to: fx.destination.appendingPathComponent("DSC00002.xmp"), modified: t0)
        let raw = try fx.write("raw", to: fx.source.appendingPathComponent("DSC00002.ARW"), modified: t0)
        try fx.write("<newer/>", to: fx.source.appendingPathComponent("DSC00002.xmp"), modified: t0.addingTimeInterval(500))

        let results = try await fx.makeEngine().process(sources: [raw], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(try String(contentsOf: fx.destination.appendingPathComponent("DSC00002.xmp")), "<edited-earlier/>")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path).sorted(), ["DSC00002.ARW", "DSC00002.xmp"])
        XCTAssertEqual(results, [.success(source: raw, destination: fx.destination.appendingPathComponent("DSC00002.ARW"), sidecars: [])])
    }
}

/// Real-world layout (darktable-style): `_DSC3895.ARW`, `_DSC3895.ARW.xmp`, `_DSC3895.ARW.rrdata`,
/// each with a different modification date.
final class IngestionPhotoWithSeveralSidecarsTests: XCTestCase {

    private func date(_ month: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = month; c.day = 10; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    func testAllSidecarsTravelWithThePhotoIntoItsOwnDateFolder() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let arw = try fx.write("raw", to: fx.source.appendingPathComponent("_DSC3895.ARW"), modified: date(7))
        try fx.write("<xmp/>", to: fx.source.appendingPathComponent("_DSC3895.ARW.xmp"), modified: date(8))
        try fx.write("{}", to: fx.source.appendingPathComponent("_DSC3895.ARW.rrdata"), modified: date(9))

        let results = try await fx.makeEngine().process(
            sources: [fx.source], destination: fx.destination, template: "{{YEAR}}/{{MONTH}}/{{NAME}}", timeOffset: 0)

        let d = fx.destination.appendingPathComponent("2026/07")
        XCTAssertEqual(results, [.success(source: arw, destination: d.appendingPathComponent("_DSC3895.ARW"),
                                          sidecars: [d.appendingPathComponent("_DSC3895.ARW.rrdata"), d.appendingPathComponent("_DSC3895.ARW.xmp")])])
        let saved = (FileManager.default.enumerator(at: fx.destination, includingPropertiesForKeys: [.isRegularFileKey])!
            .allObjects as! [URL]).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.path.replacingOccurrences(of: fx.destination.path + "/", with: "") }.sorted()
        XCTAssertEqual(saved, ["2026/07/_DSC3895.ARW", "2026/07/_DSC3895.ARW.rrdata", "2026/07/_DSC3895.ARW.xmp"])
    }

    /// A picked path may reach a file through a system link (/tmp -> /private/tmp) while folder
    /// listings come back resolved. The same sidecar must not be copied twice.
    func testPickedSidecarReachedThroughASystemLinkIsNotCopiedTwice() async throws {
        let id = UUID().uuidString
        let src = URL(fileURLWithPath: "/tmp/pi-link-\(id)/src")       // not resolved: starts with /tmp
        let dest = URL(fileURLWithPath: "/tmp/pi-link-\(id)/dest")
        defer { try? FileManager.default.removeItem(at: src.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("raw".utf8).write(to: src.appendingPathComponent("_DSC1.ARW"))
        try Data("<xmp/>".utf8).write(to: src.appendingPathComponent("_DSC1.ARW.xmp"))
        let engine = RealIngestionEngine(metadataProvider: RealMediaMetadataProvider(), pathTemplater: RealPathTemplater(),
                                         collisionJudge: RealCollisionJudge(), mediaTransferrer: RealMediaTransferrer())

        let results = try await engine.process(
            sources: [src.appendingPathComponent("_DSC1.ARW"), src.appendingPathComponent("_DSC1.ARW.xmp")],
            destination: dest, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted(), ["_DSC1.ARW", "_DSC1.ARW.xmp"])
    }
}


final class IngestionPerFileFailureTests: XCTestCase {

    func testOneUnreadableFileIsReportedFailedAndTheRestStillImport() async throws {
        let fx = try Fixture()
        let bad = fx.source.appendingPathComponent("B.JPG")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path)
            fx.cleanUp()
        }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        try fx.write("b", to: bad, modified: t0)
        let c = try fx.write("c", to: fx.source.appendingPathComponent("C.JPG"), modified: t0)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bad.path)

        let results = try await fx.makeEngine().process(
            sources: [a, bad, c], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0], .success(source: a, destination: fx.destination.appendingPathComponent("A.JPG"), sidecars: []))
        guard case let .failed(source, reason) = results[1] else { return XCTFail("expected .failed, got \(results[1])") }
        XCTAssertEqual(source, bad)
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(results[2], .success(source: c, destination: fx.destination.appendingPathComponent("C.JPG"), sidecars: []))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path).sorted(), ["A.JPG", "C.JPG"])
    }

    func testAFailedPhotoDoesNotLeaveItsSidecarBehind() async throws {
        let fx = try Fixture()
        let raw = fx.source.appendingPathComponent("A.CR2")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: raw.path); fx.cleanUp() }
        try fx.write("raw", to: raw, modified: t0)
        try fx.write("<xmp/>", to: fx.source.appendingPathComponent("A.CR2.xmp"), modified: t0)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: raw.path)

        let results = try await fx.makeEngine().process(sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path), [])
    }
}

final class IngestionOrphanSidecarTests: XCTestCase {

    func testOrphanSidecarsInAFolderAreNeverImported() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let photo = try fx.write("p", to: fx.source.appendingPathComponent("A.ARW"), modified: t0)
        try fx.write("<ok/>", to: fx.source.appendingPathComponent("A.ARW.xmp"), modified: t0)
        try fx.write("<orphan/>", to: fx.source.appendingPathComponent("GONE.xmp"), modified: t0)           // photo deleted
        try fx.write("{}", to: fx.source.appendingPathComponent("GONE2.ARW.rrdata"), modified: t0)         // photo deleted

        let results = try await fx.makeEngine().process(
            sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [
            .success(source: photo, destination: fx.destination.appendingPathComponent("A.ARW"),
                     sidecars: [fx.destination.appendingPathComponent("A.ARW.xmp")]),
            .ignoredSidecar(source: fx.source.appendingPathComponent("GONE.xmp")),
            .ignoredSidecar(source: fx.source.appendingPathComponent("GONE2.ARW.rrdata")),
        ])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path).sorted(), ["A.ARW", "A.ARW.xmp"])
    }

    func testASidecarPickedOnItsOwnIsNeverImported() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let xmp = try fx.write("<x/>", to: fx.source.appendingPathComponent("A.ARW.xmp"), modified: t0)

        let results = try await fx.makeEngine().process(sources: [xmp], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [.ignoredSidecar(source: xmp)])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path), [])
    }
}

/// Source folder lives inside the destination (e.g. import ~/Pictures/RAW into ~/Pictures).
final class IngestionSourceInsideDestinationTests: XCTestCase {

    func testAFileIsNeverADuplicateOfItself() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let raw = fx.root.appendingPathComponent("Pictures/RAW")
        let a = try fx.write("a", to: raw.appendingPathComponent("A.ARW"), modified: t0)
        let b = try fx.write("b", to: raw.appendingPathComponent("B.ARW"), modified: t0)
        let pictures = fx.root.appendingPathComponent("Pictures")      // destination CONTAINS the source

        let results = try await fx.makeEngine().process(
            sources: [raw], destination: pictures, template: "organised/{{NAME}}", timeOffset: 0)

        XCTAssertEqual(Set(results), [
            .success(source: a, destination: pictures.appendingPathComponent("organised/A.ARW")),
            .success(source: b, destination: pictures.appendingPathComponent("organised/B.ARW")),
        ])
    }

    func testARealCopyElsewhereInTheDestinationIsStillADuplicate() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let raw = fx.root.appendingPathComponent("Pictures/RAW")
        let a = try fx.write("a", to: raw.appendingPathComponent("A.ARW"), modified: t0)
        try fx.write("a", to: fx.root.appendingPathComponent("Pictures/2026/07/A.ARW"), modified: t0)   // already organised
        let pictures = fx.root.appendingPathComponent("Pictures")

        let results = try await fx.makeEngine().process(
            sources: [raw], destination: pictures, template: "organised/{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [.skipped(source: a, reason: "Duplicate found")])
    }
}

final class IngestionEdgeCaseTests: XCTestCase {

    func testNumberedSuffixKeepsCountingPastExistingSuffixes() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        try fx.write("0", to: fx.destination.appendingPathComponent("X.JPG"), modified: t0)
        try fx.write("1", to: fx.destination.appendingPathComponent("X_1.JPG"), modified: t0)
        let incoming = try fx.write("new", to: fx.source.appendingPathComponent("X.JPG"), modified: t0.addingTimeInterval(9))

        let results = try await fx.makeEngine().process(sources: [incoming], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [.renamed(source: incoming, original: fx.destination.appendingPathComponent("X.JPG"),
                                          new: fx.destination.appendingPathComponent("X_2.JPG"), sidecars: [])])
    }

    func testTwoDifferentSourceFilesWithTheSameNameBothImport() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("first", to: fx.source.appendingPathComponent("100/IMG_1.JPG"), modified: t0)
        let b = try fx.write("second-longer", to: fx.source.appendingPathComponent("101/IMG_1.JPG"), modified: t0.addingTimeInterval(5))

        let results = try await fx.makeEngine().process(sources: [a, b], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [
            .success(source: a, destination: fx.destination.appendingPathComponent("IMG_1.JPG")),
            .renamed(source: b, original: fx.destination.appendingPathComponent("IMG_1.JPG"), new: fx.destination.appendingPathComponent("IMG_1_1.JPG"), sidecars: []),
        ])
    }

    func testTheSameFileReachedTwiceInOneImportIsImportedOnce() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)

        let results = try await fx.makeEngine().process(sources: [a, fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results.count, 1)
    }

    func testNothingToImportReturnsNothingAndStillCompletesProgress() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let log = ProgressLog()

        let results = try await fx.makeEngine().process(
            sources: [], destination: fx.destination, template: "{{NAME}}", timeOffset: 0, progress: { log.record($0) })

        XCTAssertEqual(results, [])
        XCTAssertEqual(log.events, [ImportProgress(completed: 0, total: 0, currentFile: "")])
    }

    func testASourceThatDoesNotExistIsIgnored() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let results = try await fx.makeEngine().process(
            sources: [fx.source.appendingPathComponent("gone.JPG")], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)
        XCTAssertEqual(results, [])
    }
}

/// End to end: the capture date inside the file decides the folder and the duplicate check.
final class IngestionExifEndToEndTests: XCTestCase {

    func testPhotoIsFiledByItsExifCaptureDateNotItsFileDate() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let url = fx.source.appendingPathComponent("P.JPG")
        try writeJPEGWithExif(at: url, exifDate: "2019:12:31 23:30:00")
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: url.path)

        // +1 hour pushes it over New Year, so the offset-adjusted capture date drives the path.
        let results = try await fx.makeEngine().process(
            sources: [url], destination: fx.destination, template: "{{YEAR}}/{{MONTH}}/{{DAY}}/{{NAME}}", timeOffset: 3600)

        XCTAssertEqual(results, [.success(source: url, destination: fx.destination.appendingPathComponent("2020/01/01/P.JPG"))])
    }

    func testSameShotWithADifferentFileDateIsStillADuplicate() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let url = fx.source.appendingPathComponent("P.JPG")
        try writeJPEGWithExif(at: url, exifDate: "2021:05:06 07:08:09")
        let engine = fx.makeEngine()
        _ = try await engine.process(sources: [url], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: url.path)   // e.g. card copied elsewhere

        let results = try await engine.process(sources: [url], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [.skipped(source: url, reason: "Duplicate found")])
    }
}

/// Per-photo companion files written by common tools. The list is the spec, independent of the code.
final class IngestionKnownSidecarToolsTests: XCTestCase {
    static let supported = ["xmp", "rrdata",                        // Adobe/darktable/Photo Mechanic…, RAW tool
                            "pp3", "pp2", "arp",                    // RawTherapee, ART
                            "dop",                                  // DxO PhotoLab
                            "cos",                                  // Capture One
                            "vrd", "dr4",                           // Canon DPP
                            "thm",                                  // Canon/GoPro video thumbnail
                            "aae",                                  // Apple Photos edits
                            "on1", "ufraw", "exv", "mie"]           // ON1, UFRaw, Exiv2, ExifTool

    func testEverySupportedToolsSidecarTravelsWithItsPhotoInBothNamingStyles() async throws {
        for ext in Self.supported {
            let fx = try Fixture(); defer { fx.cleanUp() }
            let photo = try fx.write("raw", to: fx.source.appendingPathComponent("IMG_1.ARW"), modified: t0)
            try fx.write("s1", to: fx.source.appendingPathComponent("IMG_1.\(ext)"), modified: t0.addingTimeInterval(500))       // IMG.ext
            try fx.write("s2", to: fx.source.appendingPathComponent("IMG_1.ARW.\(ext)"), modified: t0.addingTimeInterval(900))   // IMG.ARW.ext

            let results = try await fx.makeEngine().process(sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

            XCTAssertEqual(results, [.success(
                source: photo, destination: fx.destination.appendingPathComponent("IMG_1.ARW"),
                sidecars: [fx.destination.appendingPathComponent("IMG_1.ARW.\(ext)"), fx.destination.appendingPathComponent("IMG_1.\(ext)")]
                    .sorted { $0.path < $1.path })], "extension .\(ext)")
        }
    }

    func testUpperCaseExtensionsAreRecognisedToo() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let video = try fx.write("v", to: fx.source.appendingPathComponent("MVI_0001.MOV"), modified: t0)
        try fx.write("t", to: fx.source.appendingPathComponent("MVI_0001.THM"), modified: t0)

        let results = try await fx.makeEngine().process(sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results, [.success(source: video, destination: fx.destination.appendingPathComponent("MVI_0001.MOV"),
                                          sidecars: [fx.destination.appendingPathComponent("MVI_0001.THM")])])
    }

    /// Generic or playable file types must stay ordinary files: importing a folder must not drop them.
    func testLookAlikeFileTypesAreStillImportedAsNormalFiles() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        var expected = Set<String>()
        for name in ["clip.xml", "notes.json", "readme.txt", "GL010001.LRV", "movie.mp4", "photo.jpg", "proxy.mov"] {
            try fx.write("x-\(name)", to: fx.source.appendingPathComponent(name), modified: t0); expected.insert(name)
        }

        let results = try await fx.makeEngine().process(sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(results.count, expected.count)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path)), expected)
    }
}

/// Cancels the whole import (from outside) during the first transfer, as a user pressing Cancel mid-import would.
private final class CancelDuringFirstTransfer: MediaTransferrer, @unchecked Sendable {
    let inner = RealMediaTransferrer()
    var importTask: Task<[TransferResult], Error>?
    private(set) var calls = 0
    func transfer(source: URL, to destination: URL, sidecars: [URL]) async throws -> [URL] {
        calls += 1
        if calls == 1 { importTask?.cancel() }
        return try await inner.transfer(source: source, to: destination, sidecars: sidecars)
    }
}

final class IngestionCancellationTests: XCTestCase {

    func testCancellingStopsBetweenFilesKeepsFinishedWorkAndReportsTheRest() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        try fx.write("<x/>", to: fx.source.appendingPathComponent("A.JPG.xmp"), modified: t0)
        let b = try fx.write("b", to: fx.source.appendingPathComponent("B.JPG"), modified: t0)
        let c = try fx.write("c", to: fx.source.appendingPathComponent("C.JPG"), modified: t0)
        let transferrer = CancelDuringFirstTransfer()
        let engine = RealIngestionEngine(metadataProvider: RealMediaMetadataProvider(), pathTemplater: RealPathTemplater(),
                                         collisionJudge: RealCollisionJudge(), mediaTransferrer: transferrer)

        let destination = fx.destination
        let task = Task { try await engine.process(sources: [a, b, c], destination: destination, template: "{{NAME}}", timeOffset: 0) }
        transferrer.importTask = task
        let results = try await task.value

        XCTAssertEqual(results, [
            .success(source: a, destination: fx.destination.appendingPathComponent("A.JPG"),
                     sidecars: [fx.destination.appendingPathComponent("A.JPG.xmp")]),   // the file in flight finished completely
            .cancelled(source: b),
            .cancelled(source: c),
        ])
        XCTAssertEqual(transferrer.calls, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path).sorted(), ["A.JPG", "A.JPG.xmp"])   // no .partial leftovers
    }

    func testAnUncancelledImportReportsNothingCancelled() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let results = try await fx.makeEngine().process(sources: [a], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)
        XCTAssertFalse(results.contains { if case .cancelled = $0 { return true } else { return false } })
    }
}

/// Cancels the *importing* task (from outside) while the first file's metadata is being read.
private final class CancelOutsideDuringMetadata: MediaMetadataProvider, @unchecked Sendable {
    let inner = RealMediaMetadataProvider()
    var importTask: Task<[TransferResult], Error>?
    private(set) var sawCancellationInFlight = false
    private var first = true
    func fetchMetadata(for url: URL) async throws -> MediaMetadata {
        if first { first = false; importTask?.cancel(); sawCancellationInFlight = Task.isCancelled }
        return try await inner.fetchMetadata(for: url)
    }
}

final class IngestionCancellationShieldTests: XCTestCase {

    /// A cancel must never leak into the file being imported (e.g. abort its metadata read and misfile it).
    func testCancellationDoesNotReachTheFileAlreadyInFlight() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let b = try fx.write("b", to: fx.source.appendingPathComponent("B.JPG"), modified: t0)
        let provider = CancelOutsideDuringMetadata()
        let engine = RealIngestionEngine(metadataProvider: provider, pathTemplater: RealPathTemplater(),
                                         collisionJudge: RealCollisionJudge(), mediaTransferrer: RealMediaTransferrer())
        let destination = fx.destination
        let task = Task { try await engine.process(sources: [a, b], destination: destination, template: "{{NAME}}", timeOffset: 0) }
        provider.importTask = task

        let results = try await task.value

        XCTAssertFalse(provider.sawCancellationInFlight, "the in-flight file must not observe the cancellation")
        XCTAssertEqual(results, [.success(source: a, destination: fx.destination.appendingPathComponent("A.JPG")), .cancelled(source: b)])
    }
}
