import XCTest
@testable import ImportPhotos

/// Fake at the system boundary only (NSOpenPanel + bookmark store).
final class FakeFileSelection: FileSelectionService, @unchecked Sendable {
    var nextSources: [URL] = []
    var nextDestination: URL?
    private var storedSources: [URL] = []
    private var storedDestination: URL?

    func selectSources() async throws -> [URL] {
        guard !nextSources.isEmpty else { throw CancellationError() }
        return nextSources
    }
    func selectDestination() async throws -> URL { nextDestination! }
    func persistSelection(sources: [URL]?, destination: URL?) async throws {
        if let sources { storedSources = sources }
        if let destination { storedDestination = destination }
    }
    func loadLastSelection() async -> (sources: [URL], destination: URL?) { (storedSources, storedDestination) }
}

@MainActor
final class DashboardViewModelTests: XCTestCase {

    func testChosenSourceAndDestinationSurviveRelaunch() async throws {
        let store = FakeFileSelection()
        store.nextSources = [URL(fileURLWithPath: "/Volumes/SD")]
        store.nextDestination = URL(fileURLWithPath: "/Users/me/Photos")

        let first = DashboardViewModel(fileSelection: store)
        await first.chooseSources()
        await first.chooseDestination()

        let relaunched = DashboardViewModel(fileSelection: store)
        await relaunched.restoreLastSelection()

        XCTAssertEqual(relaunched.sourceRoots, [URL(fileURLWithPath: "/Volumes/SD")])
        XCTAssertEqual(relaunched.destinationURL, URL(fileURLWithPath: "/Users/me/Photos"))
    }
}

@MainActor
final class TimeOffsetInputTests: XCTestCase {

    private func offset(_ amount: Int, _ unit: DashboardViewModel.OffsetUnit) -> TimeInterval {
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        vm.offsetAmount = amount
        vm.offsetUnit = unit
        return vm.timeOffset
    }

    func testAmountAndUnitCombineIntoSeconds() {
        XCTAssertEqual(offset(1, .hours), 3600)
        XCTAssertEqual(offset(-2, .days), -172_800)
        XCTAssertEqual(offset(90, .minutes), 5400)
    }

    func testNoOffsetByDefault() {
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        XCTAssertEqual(vm.timeOffset, 0)
    }
}

@MainActor
final class SourceBrowserTests: XCTestCase {

    func testListingShowsFoldersFirstAndOmitsHiddenFiles() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        try fx.write("", to: fx.source.appendingPathComponent("B.JPG"), modified: t0)
        try fx.write("", to: fx.source.appendingPathComponent(".DS_Store"), modified: t0)
        try fx.write("", to: fx.source.appendingPathComponent("DCIM/A.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        XCTAssertEqual(vm.items.map(\.lastPathComponent), ["DCIM", "B.JPG"])
    }

    func testImportSourcesAreTheSelectedRowsWithoutItemsInsideAnotherSelectedFolder() {
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        let folder = URL(fileURLWithPath: "/Volumes/SD/DCIM")
        let inside = URL(fileURLWithPath: "/Volumes/SD/DCIM/100/A.JPG")
        let lone = URL(fileURLWithPath: "/Volumes/SD/DCIM2/B.JPG")   // shares a name prefix, not a child

        vm.selection = [inside, lone, folder]

        XCTAssertEqual(vm.importSources, [folder, lone])
    }
}

@MainActor
final class CanImportTests: XCTestCase {
    func testRequiresSourceDestinationTemplateAndValidOffset() async throws {
        let fx = try? Fixture()
        defer { fx?.cleanUp() }
        let store = FakeFileSelection()
        store.nextSources = [fx!.source]
        store.nextDestination = URL(fileURLWithPath: "/Users/me/Photos")
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = DashboardViewModel(fileSelection: store, defaults: defaults)
        XCTAssertFalse(vm.canImport)

        await vm.chooseSources()
        await vm.chooseDestination()
        XCTAssertFalse(vm.canImport, "nothing selected")
        vm.selection = [URL(fileURLWithPath: "/Volumes/SD/DCIM")]
        XCTAssertTrue(vm.canImport)

        vm.template = "  "
        XCTAssertFalse(vm.canImport)
    }
}

@MainActor
final class SelectionLifecycleTests: XCTestCase {

    func testChoosingADifferentSourceClearsTheSelection() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let store = FakeFileSelection()
        store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        vm.selection = [URL(fileURLWithPath: "/Volumes/SD1/DCIM")]

        await vm.chooseSources()

        XCTAssertTrue(vm.selection.isEmpty)
    }

    func testSelectedItemCountIgnoresRowsInsideSelectedFolders() {
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        vm.selection = [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/a/b.jpg"), URL(fileURLWithPath: "/c.jpg")]

        XCTAssertEqual(vm.selectedItemCount, 2)
    }
}

@MainActor
final class TemplatePersistenceTests: XCTestCase {

    func testTemplateIsRememberedAcrossRelaunch() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = DashboardViewModel(fileSelection: FakeFileSelection(), defaults: defaults)
        first.template = "{{YEAR}}-{{MONTH}}/{{NAME}}"

        let relaunched = DashboardViewModel(fileSelection: FakeFileSelection(), defaults: defaults)
        XCTAssertEqual(relaunched.template, "{{YEAR}}-{{MONTH}}/{{NAME}}")
    }

    func testFreshInstallUsesDefaultTemplate() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let vm = DashboardViewModel(fileSelection: FakeFileSelection(), defaults: defaults)
        XCTAssertEqual(vm.template, "{{YEAR}}/{{MONTH}}/{{NAME}}")
    }
}

@MainActor
final class OffsetPreviewTests: XCTestCase {

    private func lateOctober() -> Date {
        var c = DateComponents(); c.year = 2023; c.month = 10; c.day = 31; c.hour = 23; c.minute = 30
        return Calendar.current.date(from: c)!
    }

    func testShowsOriginalAndOffsetAdjustedDestinationForFirstSelectedFile() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let file = try fx.write("x", to: fx.source.appendingPathComponent("P.JPG"), modified: lateOctober())
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        vm.selection = [file]
        vm.offsetAmount = 1
        vm.offsetUnit = .hours

        await vm.updatePreview()

        let preview = try XCTUnwrap(vm.preview)
        XCTAssertEqual(preview.fileName, "P.JPG")
        XCTAssertEqual(preview.originalPath, "2023/10/P.JPG")
        XCTAssertEqual(preview.adjustedPath, "2023/11/P.JPG")
        XCTAssertEqual(preview.adjustedTimestamp.timeIntervalSince(preview.originalTimestamp), 3600)
    }

    func testUsesFirstFileInsideASelectedFolder() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        try fx.write("b", to: fx.source.appendingPathComponent("DCIM/B.JPG"), modified: lateOctober())
        try fx.write("a", to: fx.source.appendingPathComponent("DCIM/A.JPG"), modified: lateOctober())
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        vm.selection = [fx.source.appendingPathComponent("DCIM")]

        await vm.updatePreview()

        XCTAssertEqual(vm.preview?.fileName, "A.JPG")
    }

    func testNoPreviewWithoutSelection() async {
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        await vm.updatePreview()
        XCTAssertNil(vm.preview)
    }
}

@MainActor
final class MultiSourceTests: XCTestCase {

    func testSeveralPickedFilesAndFoldersSurviveRelaunch() async {
        let store = FakeFileSelection()
        let picked = [URL(fileURLWithPath: "/Volumes/SD/A.JPG"), URL(fileURLWithPath: "/Volumes/SD/DCIM")]
        store.nextSources = picked

        await DashboardViewModel(fileSelection: store).chooseSources()
        let relaunched = DashboardViewModel(fileSelection: store)
        await relaunched.restoreLastSelection()

        XCTAssertEqual(relaunched.sourceRoots, picked)
    }

    func testPickedFilesAreSelectedStraightAway() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let b = try fx.write("b", to: fx.source.appendingPathComponent("B.JPG"), modified: t0)
        let store = FakeFileSelection()
        store.nextSources = [a, b]
        let vm = DashboardViewModel(fileSelection: store)

        await vm.chooseSources()

        XCTAssertEqual(vm.selection, [a, b])
    }

    func testPickingASingleFolderBrowsesItWithNothingSelected() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let store = FakeFileSelection()
        store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)

        await vm.chooseSources()

        XCTAssertTrue(vm.selection.isEmpty)
    }
}

@MainActor
final class BrowserNavigationTests: XCTestCase {

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    func testSingleFolderPickShowsItsContentsAndCannotGoAboveIt() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        try fx.write("", to: fx.source.appendingPathComponent("DCIM/A.JPG"), modified: t0)
        try fx.write("", to: fx.source.appendingPathComponent("B.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)

        await vm.chooseSources()

        XCTAssertEqual(names(vm.items), ["DCIM", "B.JPG"])
        XCTAssertFalse(vm.canGoUp)
    }

    func testOpeningAFolderThenGoingUpReturnsToTheParentListing() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        try fx.write("", to: fx.source.appendingPathComponent("DCIM/A.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        vm.open(fx.source.appendingPathComponent("DCIM"))
        XCTAssertEqual(names(vm.items), ["A.JPG"])
        XCTAssertTrue(vm.canGoUp)

        vm.goUp()
        XCTAssertEqual(names(vm.items), ["DCIM"])
        XCTAssertFalse(vm.canGoUp)
    }

    func testSeveralPickedItemsListAsTopLevelAndGoUpFromAPickedFolderReturnsToThem() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let photo = try fx.write("", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let folder = fx.source.appendingPathComponent("DCIM")
        try fx.write("", to: folder.appendingPathComponent("B.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [photo, folder]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()
        XCTAssertEqual(vm.items, [folder, photo])

        vm.open(folder)
        XCTAssertEqual(names(vm.items), ["B.JPG"])
        vm.goUp()
        XCTAssertEqual(vm.items, [folder, photo])
    }

    func testRestoredSourcesAreBrowsableToo() async throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        try fx.write("", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        await DashboardViewModel(fileSelection: store).chooseSources()

        let relaunched = DashboardViewModel(fileSelection: store)
        await relaunched.restoreLastSelection()

        XCTAssertEqual(names(relaunched.items), ["A.JPG"])
    }
}

@MainActor
final class ClickSelectionTests: XCTestCase {

    private func browsing(_ names: [String]) async throws -> (DashboardViewModel, [URL], Fixture) {
        let fx = try Fixture()
        for n in names { try fx.write("", to: fx.source.appendingPathComponent(n), modified: t0) }
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()
        return (vm, vm.items, fx)
    }

    func testPlainClickReplacesTheSelection() async throws {
        let (vm, items, fx) = try await browsing(["A.JPG", "B.JPG"]); defer { fx.cleanUp() }
        vm.click(items[0], mode: .replace)
        vm.click(items[1], mode: .replace)
        XCTAssertEqual(vm.selection, [items[1]])
    }

    func testCommandClickTogglesAnItem() async throws {
        let (vm, items, fx) = try await browsing(["A.JPG", "B.JPG", "C.JPG"]); defer { fx.cleanUp() }
        vm.click(items[0], mode: .replace)
        vm.click(items[2], mode: .toggle)
        XCTAssertEqual(vm.selection, [items[0], items[2]])
        vm.click(items[0], mode: .toggle)
        XCTAssertEqual(vm.selection, [items[2]])
    }

    func testShiftClickSelectsTheRangeFromTheAnchorInEitherDirection() async throws {
        let (vm, items, fx) = try await browsing(["A.JPG", "B.JPG", "C.JPG", "D.JPG"]); defer { fx.cleanUp() }
        vm.click(items[1], mode: .replace)
        vm.click(items[3], mode: .extend)
        XCTAssertEqual(vm.selection, [items[1], items[2], items[3]])
        vm.click(items[0], mode: .extend)
        XCTAssertEqual(vm.selection, [items[0], items[1]])
    }

    func testSelectAllSelectsEverythingShownAndClearEmptiesIt() async throws {
        let (vm, items, fx) = try await browsing(["A.JPG", "B.JPG"]); defer { fx.cleanUp() }
        vm.selectAll()
        XCTAssertEqual(vm.selection, Set(items))
        vm.clearSelection()
        XCTAssertTrue(vm.selection.isEmpty)
    }
}

@MainActor
final class SortOrderTests: XCTestCase {

    private func browse(_ files: [(String, TimeInterval)], folder: String? = nil) async throws -> (DashboardViewModel, Fixture) {
        let fx = try Fixture()
        for (name, offset) in files { try fx.write("", to: fx.source.appendingPathComponent(name), modified: t0.addingTimeInterval(offset)) }
        if let folder { try FileManager.default.createDirectory(at: fx.source.appendingPathComponent(folder), withIntermediateDirectories: true) }
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()
        return (vm, fx)
    }
    private func names(_ vm: DashboardViewModel) -> [String] { vm.items.map(\.lastPathComponent) }

    func testDefaultsToOldestFirstByModificationDateWithFoldersOnTop() async throws {
        let (vm, fx) = try await browse([("C.JPG", 0), ("A.JPG", 100), ("B.JPG", -100)], folder: "DCIM")
        defer { fx.cleanUp() }
        XCTAssertEqual(names(vm), ["DCIM", "B.JPG", "C.JPG", "A.JPG"])
    }

    func testNewestFirstAndByNameAreAvailable() async throws {
        let (vm, fx) = try await browse([("C.JPG", 0), ("A.JPG", 100), ("B.JPG", -100)])
        defer { fx.cleanUp() }
        vm.sortOrder = .dateNewestFirst
        XCTAssertEqual(names(vm), ["A.JPG", "C.JPG", "B.JPG"])
        vm.sortOrder = .name
        XCTAssertEqual(names(vm), ["A.JPG", "B.JPG", "C.JPG"])
    }
}

@MainActor
final class QuickPreviewTests: XCTestCase {

    private func browse() async throws -> (DashboardViewModel, [URL], Fixture) {
        let fx = try Fixture()
        try FileManager.default.createDirectory(at: fx.source.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
        for (i, n) in ["A.JPG", "B.JPG", "C.JPG"].enumerated() {
            try fx.write("", to: fx.source.appendingPathComponent(n), modified: t0.addingTimeInterval(Double(i)))
        }
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()
        return (vm, vm.items, fx)   // [DCIM, A, B, C]
    }

    func testPreviewsTheFirstSelectedFileInDisplayOrder() async throws {
        let (vm, items, fx) = try await browse(); defer { fx.cleanUp() }
        vm.selection = [items[3], items[2]]

        vm.requestPreview()

        XCTAssertEqual(vm.previewURL, items[2])
    }

    func testFoldersAreNotPreviewable() async throws {
        let (vm, items, fx) = try await browse(); defer { fx.cleanUp() }
        vm.selection = [items[0]]

        vm.requestPreview()

        XCTAssertNil(vm.previewURL)
    }

    func testPreviewCanBrowseEveryFileInTheFolder() async throws {
        let (vm, items, fx) = try await browse(); defer { fx.cleanUp() }
        XCTAssertEqual(vm.previewableFiles, [items[1], items[2], items[3]])
    }
}

@MainActor
final class SidecarWarningTests: XCTestCase {

    private func makeVM(canList: Bool, picked: [String], in fx: Fixture) async throws -> DashboardViewModel {
        var urls: [URL] = []
        for n in picked { urls.append(try fx.write("x", to: fx.source.appendingPathComponent(n), modified: t0)) }
        let store = FakeFileSelection(); store.nextSources = urls
        let vm = DashboardViewModel(fileSelection: store, canListFolder: { _ in canList })
        await vm.chooseSources()
        return vm
    }

    func testWarnsWhenPickedPhotosCannotHaveTheirSidecarsFound() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let vm = try await makeVM(canList: false, picked: ["A.CR2", "B.CR2"], in: fx)
        let warning = try XCTUnwrap(vm.sidecarWarning)
        XCTAssertTrue(warning.contains("2 photos"), warning)
    }

    func testNoWarningWhenTheSidecarWasPickedToo() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let vm = try await makeVM(canList: false, picked: ["A.CR2", "A.xmp"], in: fx)
        XCTAssertNil(vm.sidecarWarning)
    }

    func testNoWarningWhenTheFolderIsReadable() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let vm = try await makeVM(canList: true, picked: ["A.CR2"], in: fx)
        XCTAssertNil(vm.sidecarWarning)
    }

    func testNoWarningForAFolderPick() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        try fx.write("x", to: fx.source.appendingPathComponent("A.CR2"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store, canListFolder: { _ in false })
        await vm.chooseSources()
        vm.selection = [fx.source.appendingPathComponent("A.CR2")]
        XCTAssertNil(vm.sidecarWarning)
    }
}

@MainActor
final class SortPickedItemsTests: XCTestCase {

    func testSortOrderAlsoAppliesToIndividuallyPickedFilesAndFolders() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let c = try fx.write("", to: fx.source.appendingPathComponent("C.JPG"), modified: t0)
        let a = try fx.write("", to: fx.source.appendingPathComponent("A.JPG"), modified: t0.addingTimeInterval(100))
        let b = try fx.write("", to: fx.source.appendingPathComponent("B.JPG"), modified: t0.addingTimeInterval(-100))
        let folder = fx.source.appendingPathComponent("DCIM")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = FakeFileSelection(); store.nextSources = [c, a, b, folder]   // pick order is arbitrary
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        XCTAssertEqual(vm.items.map(\.lastPathComponent), ["DCIM", "B.JPG", "C.JPG", "A.JPG"])
        vm.sortOrder = .dateNewestFirst
        XCTAssertEqual(vm.items.map(\.lastPathComponent), ["DCIM", "A.JPG", "C.JPG", "B.JPG"])
        vm.sortOrder = .name
        XCTAssertEqual(vm.items.map(\.lastPathComponent), ["DCIM", "A.JPG", "B.JPG", "C.JPG"])
    }
}

@MainActor
final class FullNameSidecarWarningTests: XCTestCase {
    func testNoWarningWhenPickedAlongsideItsFullNameSidecar() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let dng = try fx.write("x", to: fx.source.appendingPathComponent("R1.DNG"), modified: t0)
        let xmp = try fx.write("x", to: fx.source.appendingPathComponent("R1.DNG.xmp"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [dng, xmp]
        let vm = DashboardViewModel(fileSelection: store, canListFolder: { _ in false })
        await vm.chooseSources()
        XCTAssertNil(vm.sidecarWarning)
    }
}

@MainActor
final class HiddenSidecarTests: XCTestCase {

    func testSidecarsAreNotShownWhenBrowsingAFolder() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        for n in ["A.ARW", "A.ARW.xmp", "A.ARW.rrdata", "B.JPG", "B.xmp"] {
            try fx.write("", to: fx.source.appendingPathComponent(n), modified: t0)
        }
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        XCTAssertEqual(vm.items.map(\.lastPathComponent), ["A.ARW", "B.JPG"])
    }

    func testPickedPhotoAndItsSidecarShowAsOnePhotoButTheSidecarStillImports() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let arw = try fx.write("", to: fx.source.appendingPathComponent("A.ARW"), modified: t0)
        let xmp = try fx.write("", to: fx.source.appendingPathComponent("A.ARW.xmp"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [arw, xmp]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        XCTAssertEqual(vm.items, [arw])
        XCTAssertEqual(vm.selectedItemCount, 1)
        XCTAssertEqual(Set(vm.importSources), [arw, xmp])   // sandbox: engine needs the picked sidecar to pair it
    }

    func testPickedSidecarOfAnUnselectedPhotoIsNotImported() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let a = try fx.write("", to: fx.source.appendingPathComponent("A.ARW"), modified: t0)
        let b = try fx.write("", to: fx.source.appendingPathComponent("B.ARW"), modified: t0)
        let bx = try fx.write("", to: fx.source.appendingPathComponent("B.ARW.xmp"), modified: t0)
        let store = FakeFileSelection(); store.nextSources = [a, b, bx]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        vm.click(a, mode: .replace)

        XCTAssertEqual(vm.importSources, [a])
    }
}

@MainActor
final class SelectionPersistenceEdgeTests: XCTestCase {

    func testCancellingThePickerKeepsTheCurrentSource() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()
        vm.selection = [fx.source]

        store.nextSources = []          // user cancels the next panel
        await vm.chooseSources()

        XCTAssertEqual(vm.sourceRoots, [fx.source])
        XCTAssertEqual(vm.selection, [fx.source])
    }

    func testSourceAndDestinationAreRememberedIndependently() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        let store = FakeFileSelection()
        store.nextSources = [fx.source]; store.nextDestination = fx.destination
        let first = DashboardViewModel(fileSelection: store)
        await first.chooseSources()
        await first.chooseDestination()
        store.nextSources = [fx.destination]            // change only the source later
        await first.chooseSources()

        let relaunched = DashboardViewModel(fileSelection: store)
        await relaunched.restoreLastSelection()

        XCTAssertEqual(relaunched.sourceRoots, [fx.destination])
        XCTAssertEqual(relaunched.destinationURL, fx.destination)
    }

    func testFreshInstallRestoresNothing() async {
        let vm = DashboardViewModel(fileSelection: FakeFileSelection())
        await vm.restoreLastSelection()
        XCTAssertTrue(vm.sourceRoots.isEmpty)
        XCTAssertNil(vm.destinationURL)
        XCTAssertFalse(vm.canImport)
    }
}

@MainActor
final class KnownSidecarsAreHiddenTests: XCTestCase {
    func testSidecarsFromCommonToolsNeverAppearInTheGrid() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        for n in ["A.ARW", "A.ARW.pp3", "A.dop", "A.cos", "A.vrd", "A.AAE", "A.on1", "A.ARW.xmp", "B.MOV", "B.THM", "readme.txt"] {
            try fx.write("", to: fx.source.appendingPathComponent(n), modified: t0)
        }
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()

        XCTAssertEqual(Set(vm.items.map(\.lastPathComponent)), ["A.ARW", "B.MOV", "readme.txt"])
    }
}

/// Counts how many files the view model asks metadata for.
final class CountingMetadataProvider: MediaMetadataProvider, @unchecked Sendable {
    let inner = RealMediaMetadataProvider()
    private let lock = NSLock()
    private var names: [String] = []
    var requested: [String] { lock.lock(); defer { lock.unlock() }; return names.sorted() }
    func fetchMetadata(for url: URL) async throws -> MediaMetadata {
        lock.lock(); names.append(url.lastPathComponent); lock.unlock()
        return try await inner.fetchMetadata(for: url)
    }
}

@MainActor
final class CaptureDateSortTests: XCTestCase {

    /// File dates say B < A < C; capture (EXIF) dates say A(2022) < C(2023) < B(2024).
    private func browse(counting provider: CountingMetadataProvider = CountingMetadataProvider(),
                        extra: (Fixture) throws -> Void = { _ in }) async throws -> (DashboardViewModel, Fixture, CountingMetadataProvider) {
        let fx = try Fixture()
        for (name, exif, modified) in [("A.JPG", "2022:03:01 10:00:00", t0), ("B.JPG", "2024:03:01 10:00:00", t0.addingTimeInterval(-100)),
                                       ("C.JPG", "2023:03:01 10:00:00", t0.addingTimeInterval(100))] {
            let url = fx.source.appendingPathComponent(name)
            try writeJPEGWithExif(at: url, exifDate: exif)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        try extra(fx)
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store, metadataProvider: provider)
        await vm.chooseSources()
        return (vm, fx, provider)
    }
    private func names(_ vm: DashboardViewModel) -> [String] { vm.items.map(\.lastPathComponent) }

    func testOrdersByCaptureDateOnceLoadedOldestFirstThenNewestFirst() async throws {
        let (vm, fx, _) = try await browse(); defer { fx.cleanUp() }
        vm.sortOrder = .captureDateOldestFirst
        await vm.loadCaptureDates()
        XCTAssertEqual(names(vm), ["A.JPG", "C.JPG", "B.JPG"])
        vm.sortOrder = .captureDateNewestFirst
        XCTAssertEqual(names(vm), ["B.JPG", "C.JPG", "A.JPG"])
    }

    func testTheGridNeverWaitsForMetadata_UntilLoadedItFallsBackToTheFileDate() async throws {
        let (vm, fx, provider) = try await browse(); defer { fx.cleanUp() }
        vm.sortOrder = .captureDateOldestFirst
        XCTAssertEqual(names(vm), ["B.JPG", "A.JPG", "C.JPG"], "file-date order until capture dates arrive")
        XCTAssertEqual(provider.requested, [], "choosing the sort reads nothing by itself")
    }

    func testFoldersStayOnTopAndOnlyPhotosAreRead() async throws {
        let (vm, fx, provider) = try await browse { fx in
            try FileManager.default.createDirectory(at: fx.source.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
            try fx.write("<x/>", to: fx.source.appendingPathComponent("A.JPG.xmp"), modified: t0)   // hidden sidecar: must not be read
        }
        defer { fx.cleanUp() }
        vm.sortOrder = .captureDateNewestFirst
        await vm.loadCaptureDates()
        XCTAssertEqual(names(vm), ["DCIM", "B.JPG", "C.JPG", "A.JPG"])
        XCTAssertEqual(provider.requested, ["A.JPG", "B.JPG", "C.JPG"])
    }

    func testEachFileIsReadOnlyOnceAcrossRepeatedLoadsAndSortFlips() async throws {
        let (vm, fx, provider) = try await browse(); defer { fx.cleanUp() }
        vm.sortOrder = .captureDateOldestFirst
        await vm.loadCaptureDates()
        vm.sortOrder = .captureDateNewestFirst
        await vm.loadCaptureDates()
        await vm.loadCaptureDates()
        XCTAssertEqual(provider.requested, ["A.JPG", "B.JPG", "C.JPG"])
        XCTAssertFalse(vm.isLoadingCaptureDates)
    }

    func testOtherSortOrdersNeverReadMetadata() async throws {
        let (vm, fx, provider) = try await browse(); defer { fx.cleanUp() }
        vm.sortOrder = .dateOldestFirst; await vm.loadCaptureDates()
        vm.sortOrder = .name; await vm.loadCaptureDates()
        XCTAssertEqual(provider.requested, [])
    }

    func testOpeningASubfolderLoadsThatFoldersCaptureDates() async throws {
        let (vm, fx, provider) = try await browse { fx in
            let inner = fx.source.appendingPathComponent("Trip/X.JPG"); try writeJPEGWithExif(at: inner, exifDate: "2020:01:01 00:00:00")
        }
        defer { fx.cleanUp() }
        vm.sortOrder = .captureDateOldestFirst
        vm.open(fx.source.appendingPathComponent("Trip"))
        await vm.loadCaptureDates()
        XCTAssertEqual(provider.requested, ["X.JPG"])
    }

    func testPickedFilesAreSortedByCaptureDateToo() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        var picked: [URL] = []
        for (name, exif) in [("Z.JPG", "2020:01:01 00:00:00"), ("Y.JPG", "2021:01:01 00:00:00")] {
            let url = fx.source.appendingPathComponent(name); try writeJPEGWithExif(at: url, exifDate: exif); picked.append(url)
        }
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: picked[0].path)
        try FileManager.default.setAttributes([.modificationDate: t0.addingTimeInterval(-500)], ofItemAtPath: picked[1].path)   // file dates say Y first
        let store = FakeFileSelection(); store.nextSources = picked
        let vm = DashboardViewModel(fileSelection: store)
        await vm.chooseSources()
        vm.sortOrder = .captureDateOldestFirst
        await vm.loadCaptureDates()
        XCTAssertEqual(names(vm), ["Z.JPG", "Y.JPG"])
    }

    func testALargeFolderLoadsEveryFileExactlyOnceAndQuickly() async throws {
        let fx = try Fixture(); defer { fx.cleanUp() }
        for i in 0..<300 {
            let url = fx.source.appendingPathComponent(String(format: "IMG_%04d.JPG", i))
            try writeJPEGWithExif(at: url, exifDate: String(format: "2020:01:01 00:%02d:%02d", (299 - i) / 60, (299 - i) % 60))   // reverse of name order
        }
        let provider = CountingMetadataProvider()
        let store = FakeFileSelection(); store.nextSources = [fx.source]
        let vm = DashboardViewModel(fileSelection: store, metadataProvider: provider)
        await vm.chooseSources()
        vm.sortOrder = .captureDateOldestFirst

        let started = Date()
        await vm.loadCaptureDates()

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(provider.requested.count, 300)
        XCTAssertEqual(Set(provider.requested).count, 300)
        XCTAssertEqual(vm.items.first?.lastPathComponent, "IMG_0299.JPG")     // earliest capture = highest number
        XCTAssertEqual(vm.items.last?.lastPathComponent, "IMG_0000.JPG")
    }
}
