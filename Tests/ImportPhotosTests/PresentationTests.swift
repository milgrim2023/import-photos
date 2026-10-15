import XCTest
@testable import ImportPhotos

/// The text and state the views show, decided in plain types so no UI is needed to test them.
final class BottomBarPresentationTests: XCTestCase {

    private func idle(selected: Int, canImport: Bool = true) -> BottomBarPresentation {
        BottomBarPresentation(selectedItemCount: selected, canImport: canImport, isRunning: false, fractionCompleted: 0, currentFile: "")
    }

    func testIdleAsksForASelectionWhenNothingIsSelected() {
        let bar = idle(selected: 0, canImport: false)
        XCTAssertEqual(bar.mode, .idle)
        XCTAssertEqual(bar.summary, "Select files or folders to import")
        XCTAssertFalse(bar.importEnabled)
    }

    func testIdleSummaryPluralisesTheItemCount() {
        XCTAssertEqual(idle(selected: 1).summary, "1 item selected")
        XCTAssertEqual(idle(selected: 12).summary, "12 items selected")
    }

    func testImportIsEnabledOnlyWhenTheViewModelAllowsIt() {
        XCTAssertTrue(idle(selected: 2, canImport: true).importEnabled)
        XCTAssertFalse(idle(selected: 2, canImport: false).importEnabled)
    }

    func testRunningShowsRoundedPercentAndTheCurrentFileAndNeverEnablesImport() {
        let bar = BottomBarPresentation(selectedItemCount: 5, canImport: true, isRunning: true, fractionCompleted: 0.666, currentFile: "IMG_1.ARW")
        XCTAssertEqual(bar.mode, .running)
        XCTAssertEqual(bar.percentText, "67%")
        XCTAssertEqual(bar.currentFile, "IMG_1.ARW")
        XCTAssertFalse(bar.importEnabled)
    }

    func testPercentRangeEndsAre0And100() {
        func pct(_ f: Double) -> String { BottomBarPresentation(selectedItemCount: 1, canImport: true, isRunning: true, fractionCompleted: f, currentFile: "").percentText }
        XCTAssertEqual(pct(0), "0%")
        XCTAssertEqual(pct(1), "100%")
    }
}

final class ResultsPresentationTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/src/A.JPG"), b = URL(fileURLWithPath: "/src/B.JPG"), c = URL(fileURLWithPath: "/src/C.JPG")

    func testACleanImportHasASimpleTitleThreeStatsAndNoNotesOrLists() {
        let r = ResultsPresentation(report: ImportReport(results: [
            .success(source: a, destination: URL(fileURLWithPath: "/d/A.JPG")),
            .skipped(source: b, reason: "Duplicate found"),
        ]))
        XCTAssertEqual(r.title, "Import Complete")
        XCTAssertEqual(r.stats.map(\.title), ["Photos imported", "Skipped (duplicates)", "Renamed"])
        XCTAssertEqual(r.stats.map(\.value), [1, 1, 0])
        XCTAssertNil(r.sidecarNote)
        XCTAssertNil(r.ignoredNote)
        XCTAssertEqual(r.sections.map(\.title), ["Skipped"])
    }

    func testFailuresChangeTheTitleAddAProblemStatAndComeFirstWithTheirReason() {
        let r = ResultsPresentation(report: ImportReport(results: [
            .failed(source: c, reason: "No permission"),
            .skipped(source: b, reason: "Duplicate found"),
        ]))
        XCTAssertEqual(r.title, "Import Finished with Problems")
        XCTAssertEqual(r.stats.map(\.title), ["Photos imported", "Skipped (duplicates)", "Renamed", "Failed"])
        XCTAssertEqual(r.stats.last?.isProblem, true)
        XCTAssertEqual(r.sections.map(\.title), ["Failed", "Skipped"])
        XCTAssertEqual(r.sections[0].rows, [.init(primary: "C.JPG", secondary: "No permission")])
    }

    func testRenamedRowsShowOldAndNewNames() {
        let r = ResultsPresentation(report: ImportReport(results: [
            .renamed(source: a, original: URL(fileURLWithPath: "/d/A.JPG"), new: URL(fileURLWithPath: "/d/A_1.JPG")),
        ]))
        XCTAssertEqual(r.sections.map(\.title), ["Renamed"])
        XCTAssertEqual(r.sections[0].rows, [.init(primary: "A.JPG → A_1.JPG", secondary: nil)])
    }

    func testSidecarsCopiedAreNotedAndPluralised() {
        func note(_ n: Int) -> String? {
            let copied = (0..<n).map { URL(fileURLWithPath: "/d/A\($0).xmp") }
            return ResultsPresentation(report: ImportReport(results: [.success(source: a, destination: URL(fileURLWithPath: "/d/A.JPG"), sidecars: copied)])).sidecarNote
        }
        XCTAssertNil(note(0))
        XCTAssertEqual(note(1), "1 sidecar file (.xmp etc.) copied with their photos.")
        XCTAssertEqual(note(3), "3 sidecar files (.xmp etc.) copied with their photos.")
    }

    func testIgnoredOrphanSidecarsAreNotedListedAndPluralised() {
        let one = ResultsPresentation(report: ImportReport(results: [.ignoredSidecar(source: URL(fileURLWithPath: "/s/GONE.xmp"))]))
        XCTAssertEqual(one.ignoredNote, "1 sidecar file had no photo and was ignored.")
        XCTAssertEqual(one.sections.map(\.title), ["Ignored sidecars (no photo)"])
        XCTAssertEqual(one.sections[0].rows, [.init(primary: "GONE.xmp", secondary: nil)])

        let two = ResultsPresentation(report: ImportReport(results: [
            .ignoredSidecar(source: URL(fileURLWithPath: "/s/1.xmp")), .ignoredSidecar(source: URL(fileURLWithPath: "/s/2.xmp"))]))
        XCTAssertEqual(two.ignoredNote, "2 sidecar files had no photo and were ignored.")
    }

    func testSectionOrderIsFailedSkippedIgnoredRenamed() {
        let r = ResultsPresentation(report: ImportReport(results: [
            .renamed(source: a, original: URL(fileURLWithPath: "/d/A.JPG"), new: URL(fileURLWithPath: "/d/A_1.JPG")),
            .ignoredSidecar(source: URL(fileURLWithPath: "/s/x.xmp")),
            .skipped(source: b, reason: "Duplicate found"),
            .failed(source: c, reason: "boom"),
        ]))
        XCTAssertEqual(r.sections.map(\.title), ["Failed", "Skipped", "Ignored sidecars (no photo)", "Renamed"])
    }
}

@MainActor
final class DashboardLabelTests: XCTestCase {

    func testOffsetLabelIsSignedForPositiveAndPlainOtherwise() {
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        vm.offsetAmount = 2;  XCTAssertEqual(vm.offsetLabel, "+2")
        vm.offsetAmount = 0;  XCTAssertEqual(vm.offsetLabel, "0")
        vm.offsetAmount = -3; XCTAssertEqual(vm.offsetLabel, "-3")
    }

    func testDestinationLabelShowsThePathOrAPlaceholder() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let store = FakeFileSelection(); store.nextDestination = fx.destination
        let vm = DashboardViewModel(fileSelection: store)
        XCTAssertEqual(vm.destinationLabel, "None chosen")
        await vm.chooseDestination()
        XCTAssertEqual(vm.destinationLabel, fx.destination.path)
    }

    func testBrowserTitleIsTheFolderPathOrSelectedItems() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let photo = try fx.write("", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()
        XCTAssertEqual(vm.browserTitle, fx.source.path)

        store.nextSources = [photo, photo.deletingLastPathComponent().appendingPathComponent("B.JPG")]
        await vm.chooseSources()
        XCTAssertEqual(vm.browserTitle, "Selected items")
    }

    func testPreviewIsPossibleOnlyWhenAFileIsSelected() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let photo = try fx.write("", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let folder = fx.source.appendingPathComponent("DCIM")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        XCTAssertFalse(vm.canPreview)            // nothing selected
        vm.click(folder, mode: .replace)
        XCTAssertFalse(vm.canPreview)            // a folder can't be previewed
        vm.click(photo, mode: .replace)
        XCTAssertTrue(vm.canPreview)
    }
}

@MainActor
final class ImportFromDashboardTests: XCTestCase {

    func testStartingFromTheDashboardImportsTheSelectionWithItsTemplateAndOffset() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        var c = DateComponents(); c.year = 2023; c.month = 10; c.day = 31; c.hour = 23; c.minute = 30
        let late = Calendar.current.date(from: c)!
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: late)
        try fx.write("b", to: fx.source.appendingPathComponent("B.JPG"), modified: late)   // not selected
        let store = FakeFileSelection(); store.nextSources = [a, fx.source.appendingPathComponent("B.JPG")]; store.nextDestination = fx.destination
        let suite = "test-\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let dashboard = DashboardViewModel(fileSelection: store, defaults: defaults)
        await dashboard.chooseSources(); await dashboard.chooseDestination()
        dashboard.click(a, mode: .replace)
        dashboard.template = "{{YEAR}}/{{MONTH}}/{{NAME}}"
        dashboard.offsetAmount = 1; dashboard.offsetUnit = .hours
        let importer = ImportViewModel(engine: fx.makeEngine())

        await importer.start(using: dashboard)

        XCTAssertEqual(importer.report?.importedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fx.destination.appendingPathComponent("2023/11/A.JPG").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fx.destination.appendingPathComponent("2023/11/B.JPG").path))
    }

    func testStartingWithoutADestinationDoesNothing() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [a]
        let dashboard = DashboardViewModel(fileSelection: store)
        await dashboard.chooseSources()
        let importer = ImportViewModel(engine: fx.makeEngine())

        await importer.start(using: dashboard)

        XCTAssertNil(importer.report)
        XCTAssertFalse(importer.isRunning)
    }
}

final class CancelPresentationTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/s/A.JPG"), b = URL(fileURLWithPath: "/s/B.JPG"), c = URL(fileURLWithPath: "/s/C.JPG")

    func testReportCountsCancelledFiles() {
        let report = ImportReport(results: [.success(source: a, destination: URL(fileURLWithPath: "/d/A.JPG")), .cancelled(source: b), .cancelled(source: c)])
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(report.cancelledCount, 2)
        XCTAssertTrue(report.wasCancelled)
        XCTAssertFalse(ImportReport(results: []).wasCancelled)
    }

    func testResultsAnnounceTheCancellationAndHowManyWereNotImported() {
        let one = ResultsPresentation(report: ImportReport(results: [.cancelled(source: b)]))
        XCTAssertEqual(one.title, "Import Cancelled")
        XCTAssertEqual(one.cancelledNote, "1 photo was not imported because the import was cancelled.")
        let two = ResultsPresentation(report: ImportReport(results: [.cancelled(source: b), .cancelled(source: c)]))
        XCTAssertEqual(two.cancelledNote, "2 photos were not imported because the import was cancelled.")
    }

    func testCancellationTitleWinsOverFailures() {
        let r = ResultsPresentation(report: ImportReport(results: [.failed(source: a, reason: "x"), .cancelled(source: b)]))
        XCTAssertEqual(r.title, "Import Cancelled")
        XCTAssertEqual(r.stats.last?.title, "Failed")
    }

    func testNoCancelNoteWhenNothingWasCancelled() {
        XCTAssertNil(ResultsPresentation(report: ImportReport(results: [])).cancelledNote)
    }

    func testBottomBarOffersCancelOnlyWhileRunningAndShowsCancellingOnce() {
        func bar(running: Bool, cancelling: Bool) -> BottomBarPresentation {
            BottomBarPresentation(selectedItemCount: 1, canImport: true, isRunning: running, isCancelling: cancelling, fractionCompleted: 0.5, currentFile: "A")
        }
        XCTAssertFalse(bar(running: false, cancelling: false).showsCancel)
        XCTAssertTrue(bar(running: true, cancelling: false).showsCancel)
        XCTAssertTrue(bar(running: true, cancelling: false).cancelEnabled)
        XCTAssertEqual(bar(running: true, cancelling: false).cancelTitle, "Cancel")
        XCTAssertFalse(bar(running: true, cancelling: true).cancelEnabled)
        XCTAssertEqual(bar(running: true, cancelling: true).cancelTitle, "Cancelling…")
    }
}
