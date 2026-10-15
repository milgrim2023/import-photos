import XCTest
@testable import ImportPhotos

@MainActor
final class FileSelectionServiceTests: XCTestCase {
    
    func testPersistAndLoad() async throws {
        let manager = RealSecurityBookmarkManager()
        let service = RealFileSelectionService(bookmarkManager: manager)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try await service.persistSelection(sources: [tempDir], destination: nil)
        let (sources, destination) = await service.loadLastSelection()
        
        XCTAssertEqual(sources.map(\.lastPathComponent), [tempDir.lastPathComponent])
        XCTAssertNil(destination)
    }
}

final class SecurityBookmarkManagerTests: XCTestCase {
    func testSaveAndLoad() throws {
        let manager = RealSecurityBookmarkManager()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let key = "test_key"
        try manager.saveBookmark(for: tempDir, key: key)
        
        let loaded = manager.loadBookmark(for: key)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.lastPathComponent, tempDir.lastPathComponent)
    }

    func testSaveAndLoadSeveralBookmarksKeepsOrder() throws {
        let manager = RealSecurityBookmarkManager()
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let a = try fx.write("a", to: fx.source.appendingPathComponent("A.JPG"), modified: t0)
        let b = fx.destination

        try manager.saveBookmarks(for: [a, b], key: "multi_test")

        XCTAssertEqual(manager.loadBookmarks(for: "multi_test").map(\.lastPathComponent), ["A.JPG", "destination"])
    }
}

final class BookmarkStoreRobustnessTests: XCTestCase {

    func testAnUnknownKeyLoadsNothing() {
        let manager = RealSecurityBookmarkManager()
        XCTAssertNil(manager.loadBookmark(for: "never-saved-\(UUID().uuidString)"))
        XCTAssertEqual(manager.loadBookmarks(for: "never-saved-\(UUID().uuidString)"), [])
    }

    func testCorruptBookmarkDataIsSkippedInsteadOfCrashing() throws {
        let key = "corrupt-\(UUID().uuidString)"
        let fx = try Fixture(); defer { fx.cleanUp() }
        let manager = RealSecurityBookmarkManager()
        try manager.saveBookmarks(for: [fx.source], key: key)
        // Inject garbage between two good entries, as a damaged preferences file might.
        let good = UserDefaults.standard.array(forKey: "bookmarks_\(key)") as! [Data]
        UserDefaults.standard.set([Data("garbage".utf8)] + good, forKey: "bookmarks_\(key)")
        defer { UserDefaults.standard.removeObject(forKey: "bookmarks_\(key)") }

        XCTAssertEqual(manager.loadBookmarks(for: key).map(\.lastPathComponent), [fx.source.lastPathComponent])
    }

    func testAFolderThatNoLongerExistsDoesNotRestore() throws {
        let key = "gone-\(UUID().uuidString)"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manager = RealSecurityBookmarkManager()
        try manager.saveBookmark(for: dir, key: key)
        defer { UserDefaults.standard.removeObject(forKey: "bookmark_\(key)") }

        try FileManager.default.removeItem(at: dir)          // e.g. SD card ejected / folder deleted

        XCTAssertNil(manager.loadBookmark(for: key))
    }
}
