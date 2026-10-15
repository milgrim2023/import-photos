import SwiftUI
import ImportPhotos

@main
struct PhotoImportApp: App {
    @State private var dashboard: DashboardViewModel
    @State private var importer: ImportViewModel

    init() {
        var selection: FileSelectionService = RealFileSelectionService(bookmarkManager: RealSecurityBookmarkManager())
        var defaults = UserDefaults.standard
        var canListFolder: (URL) -> Bool = { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil }
        #if DEBUG
        if UITestMode.isEnabled {
            let env = UITestMode.makeEnvironment()
            (selection, defaults, canListFolder) = (env.selection, env.defaults, env.canListFolder)
        }
        #endif

        var transferrer: MediaTransferrer = RealMediaTransferrer()
        #if DEBUG
        if UITestMode.isEnabled && UITestMode.slowImport { transferrer = SlowTransferrer() }
        #endif
        let engine = RealIngestionEngine(
            metadataProvider: RealMediaMetadataProvider(),
            pathTemplater: RealPathTemplater(),
            collisionJudge: RealCollisionJudge(),
            mediaTransferrer: transferrer)
        _dashboard = State(initialValue: DashboardViewModel(fileSelection: selection, defaults: defaults, canListFolder: canListFolder))
        _importer = State(initialValue: ImportViewModel(engine: engine))
    }

    var body: some Scene {
        WindowGroup("Import Photos") {
            RootView(dashboard: dashboard, importer: importer)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
