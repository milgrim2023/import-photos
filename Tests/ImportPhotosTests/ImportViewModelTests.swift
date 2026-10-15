import XCTest
@testable import ImportPhotos

@MainActor
final class ImportViewModelReportTests: XCTestCase {

    func testReportCountsImportedSkippedRenamedAndItemizesThem() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        // destination already has: dup.jpg (identical) and clash.jpg (different)
        let dupDest = try fx.write("same", to: fx.destination.appendingPathComponent("dup.jpg"), modified: t0)
        let clashDest = try fx.write("old", to: fx.destination.appendingPathComponent("clash.jpg"), modified: t0)
        let fresh = try fx.write("n", to: fx.source.appendingPathComponent("a_new.jpg"), modified: t0)
        let dup = try fx.write("same", to: fx.source.appendingPathComponent("dup.jpg"), modified: t0)
        let clash = try fx.write("new", to: fx.source.appendingPathComponent("clash.jpg"), modified: t0.addingTimeInterval(5))
        _ = (dupDest, clashDest)

        let vm = ImportViewModel(engine: fx.makeEngine())
        await vm.start(sources: [fresh, dup, clash], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        let report = try XCTUnwrap(vm.report)
        XCTAssertEqual(report.importedCount, 2)   // new + renamed
        XCTAssertEqual(report.skipped.map(\.source), [dup])
        XCTAssertEqual(report.renamed.map(\.new), [fx.destination.appendingPathComponent("clash_1.jpg")])
        XCTAssertFalse(vm.isRunning)
    }
}

/// Engine stub that reports one progress event and then waits, so tests can observe mid-import state.
final class SuspendedEngine: IngestionEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false
    let event: ImportProgress
    init(event: ImportProgress) { self.event = event }

    func process(sources: [URL], destination: URL, template: String, timeOffset: TimeInterval,
                 progress: @escaping @Sendable (ImportProgress) -> Void) async throws -> [TransferResult] {
        progress(event)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock(); defer { lock.unlock() }
            if released { c.resume() } else { gate = c }
        }
        return []
    }
    func release() {
        lock.lock(); defer { lock.unlock() }
        released = true
        gate?.resume(); gate = nil
    }
}

@MainActor
final class ImportViewModelProgressTests: XCTestCase {

    func testExposesPercentAndCurrentFileWhileRunning() async throws {
        let engine = SuspendedEngine(event: ImportProgress(completed: 1, total: 4, currentFile: "B.JPG"))
        let vm = ImportViewModel(engine: engine)

        let run = Task { await vm.start(sources: [], destination: URL(fileURLWithPath: "/tmp"), template: "{{NAME}}", timeOffset: 0) }
        while vm.currentFile.isEmpty { await Task.yield() }

        XCTAssertTrue(vm.isRunning)
        XCTAssertEqual(vm.fractionCompleted, 0.25, accuracy: 0.0001)
        XCTAssertEqual(vm.currentFile, "B.JPG")

        engine.release()
        await run.value
        XCTAssertFalse(vm.isRunning)
    }
}

struct FailingEngine: IngestionEngine {
    struct Boom: LocalizedError { var errorDescription: String? { "disk full" } }
    func process(sources: [URL], destination: URL, template: String, timeOffset: TimeInterval,
                 progress: @escaping @Sendable (ImportProgress) -> Void) async throws -> [TransferResult] { throw Boom() }
}

@MainActor
final class ImportViewModelFailureTests: XCTestCase {
    func testEngineFailureSurfacesMessageAndStopsRunning() async {
        let vm = ImportViewModel(engine: FailingEngine())
        await vm.start(sources: [], destination: URL(fileURLWithPath: "/tmp"), template: "{{NAME}}", timeOffset: 0)

        XCTAssertEqual(vm.errorMessage, "disk full")
        XCTAssertNil(vm.report)
        XCTAssertFalse(vm.isRunning)
    }
}

@MainActor
final class ImportViewModelSidecarAndFailureReportTests: XCTestCase {

    func testReportNotesSidecarsCopiedAndListsFailuresAndNeverCopiesASidecarForADuplicate() async throws {
        let fx = try Fixture()
        let bad = fx.source.appendingPathComponent("bad.jpg")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path); fx.cleanUp() }
        try fx.write("same", to: fx.destination.appendingPathComponent("dup.jpg"), modified: t0)
        let fresh = try fx.write("n", to: fx.source.appendingPathComponent("a_new.jpg"), modified: t0)
        try fx.write("<x/>", to: fx.source.appendingPathComponent("a_new.jpg.xmp"), modified: t0)
        try fx.write("{}", to: fx.source.appendingPathComponent("a_new.jpg.rrdata"), modified: t0)
        let dup = try fx.write("same", to: fx.source.appendingPathComponent("dup.jpg"), modified: t0)
        try fx.write("<newer/>", to: fx.source.appendingPathComponent("dup.jpg.xmp"), modified: t0.addingTimeInterval(900))
        try fx.write("b", to: bad, modified: t0)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bad.path)

        let vm = ImportViewModel(engine: fx.makeEngine())
        await vm.start(sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        let report = try XCTUnwrap(vm.report)
        XCTAssertEqual(report.importedCount, 1)                       // photos only
        XCTAssertEqual(report.sidecarCount, 2)                        // implicit, but noted
        XCTAssertEqual(report.skipped.map(\.source), [dup])
        XCTAssertEqual(report.failed.map(\.source), [bad])
        XCTAssertFalse(report.failed[0].reason.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fx.destination.path).sorted(),
                       ["a_new.jpg", "a_new.jpg.rrdata", "a_new.jpg.xmp", "dup.jpg"])
        XCTAssertNotNil(fresh)
    }
}

@MainActor
final class ImportViewModelIgnoredSidecarReportTests: XCTestCase {
    func testReportListsIgnoredOrphanSidecars() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        try fx.write("p", to: fx.source.appendingPathComponent("A.ARW"), modified: t0)
        let orphan = try fx.write("<x/>", to: fx.source.appendingPathComponent("GONE.xmp"), modified: t0)

        let vm = ImportViewModel(engine: fx.makeEngine())
        await vm.start(sources: [fx.source], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        let report = try XCTUnwrap(vm.report)
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(report.ignoredSidecars, [orphan])
    }
}

@MainActor
final class ImportViewModelRerunTests: XCTestCase {

    func testANewRunClearsThePreviousReportAndError() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let photo = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let vm = ImportViewModel(engine: fx.makeEngine())
        await vm.start(sources: [photo], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)
        XCTAssertEqual(vm.report?.importedCount, 1)
        vm.errorMessage = "stale error from earlier"

        await vm.start(sources: [photo], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.report?.importedCount, 0)
        XCTAssertEqual(vm.report?.skippedCount, 1)
    }

    func testReportCountsMatchItsLists() async throws {
        let fx = try Fixture()
        let bad = fx.source.appendingPathComponent("bad.JPG")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path); fx.cleanUp() }
        try fx.write("old", to: fx.destination.appendingPathComponent("clash.JPG"), modified: t0)
        let clash = try fx.write("new", to: fx.source.appendingPathComponent("clash.JPG"), modified: t0.addingTimeInterval(5))
        try fx.write("b", to: bad, modified: t0)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bad.path)

        let vm = ImportViewModel(engine: fx.makeEngine())
        await vm.start(sources: [clash, bad], destination: fx.destination, template: "{{NAME}}", timeOffset: 0)

        let report = try XCTUnwrap(vm.report)
        XCTAssertEqual([report.importedCount, report.renamedCount, report.failedCount, report.skippedCount], [1, 1, 1, 0])
    }
}

/// Keeps "importing" until cancelled, then reports the file it never reached.
final class WaitsForCancelEngine: IngestionEngine, @unchecked Sendable {
    func process(sources: [URL], destination: URL, template: String, timeOffset: TimeInterval,
                 progress: @escaping @Sendable (ImportProgress) -> Void) async throws -> [TransferResult] {
        progress(ImportProgress(completed: 0, total: 1, currentFile: "A.JPG"))
        while !Task.isCancelled { try? await Task.sleep(nanoseconds: 2_000_000) }
        return [.cancelled(source: URL(fileURLWithPath: "/s/A.JPG"))]
    }
}

@MainActor
final class ImportViewModelCancelTests: XCTestCase {

    func testCancelStopsTheRunningImportAndYieldsACancelledReport() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [a]; store.nextDestination = fx.destination
        let dashboard = DashboardViewModel(fileSelection: store)
        await dashboard.chooseSources(); await dashboard.chooseDestination()
        let importer = ImportViewModel(engine: WaitsForCancelEngine())

        importer.beginImport(using: dashboard)
        while importer.currentFile.isEmpty { await Task.yield() }
        XCTAssertTrue(importer.isRunning)
        XCTAssertFalse(importer.isCancelling)

        importer.cancel()
        XCTAssertTrue(importer.isCancelling)
        while importer.isRunning { await Task.yield() }

        XCTAssertEqual(importer.report?.cancelledCount, 1)
        XCTAssertFalse(importer.isCancelling, "cancelling state clears when the run ends")
    }

    func testCancelWhenNothingIsRunningDoesNothing() {
        let importer = ImportViewModel(engine: WaitsForCancelEngine())
        importer.cancel()
        XCTAssertFalse(importer.isCancelling)
    }
}
