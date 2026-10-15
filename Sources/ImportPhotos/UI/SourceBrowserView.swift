import SwiftUI
import AppKit
import QuickLook

/// Left pane: thumbnail grid with Finder-style selection (click, ⌘-click, ⇧-click, ⌘A).
/// A selected folder imports recursively; double-click opens it.
struct SourceBrowserView: View {
    @Bindable var dashboard: DashboardViewModel
    @FocusState private var gridFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if dashboard.sourceRoots.isEmpty {
                emptyState
            } else {
                header
                Divider()
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Button { dashboard.goUp() } label: { Image(systemName: "chevron.left") }
                .disabled(!dashboard.canGoUp)
                .accessibilityLabel("Back").accessibilityIdentifier("back-button")
            Image(systemName: "sdcard")
            Text(dashboard.browserTitle).lineLimit(1).truncationMode(.middle).accessibilityIdentifier("browser-title")
            Spacer()
            Picker("Sort", selection: $dashboard.sortOrder) {
                ForEach(FileSortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().fixedSize().accessibilityIdentifier("sort-picker")
            if dashboard.isLoadingCaptureDates {
                ProgressView().controlSize(.small).help("Reading capture dates…").accessibilityIdentifier("capture-date-spinner")
            }
            Button("Preview") { dashboard.requestPreview() }
                .disabled(!dashboard.canPreview).accessibilityIdentifier("preview-button")
            Button("Select All") { dashboard.selectAll() }.accessibilityIdentifier("select-all")
            Button("Change…") { Task { await dashboard.chooseSources() } }.accessibilityIdentifier("change-source")
        }
        .padding(8)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(dashboard.items, id: \.self) { url in cell(url) }
            }
            .padding(12)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { dashboard.clearSelection(); gridFocused = true })
        }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .quickLookPreview($dashboard.previewURL, in: dashboard.previewableFiles)
        .onKeyPress(.space) {
            dashboard.requestPreview()
            return dashboard.selection.isEmpty ? .ignored : .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            dashboard.selectAll()
            return .handled
        }
    }

    private func cell(_ url: URL) -> some View {
        let isDirectory = DirectoryListing.isDirectory(url)
        let selected = dashboard.selection.contains(url)
        return VStack(spacing: 4) {
            ThumbnailView(url: url, isDirectory: isDirectory).frame(width: 120, height: 90)
            Text(url.lastPathComponent).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityIdentifier("cell-\(url.lastPathComponent)")
        .accessibilityAddTraits(.isButton)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            // Fires on the first click (no double-click wait), so Shift/⌘ are still held.
            gridFocused = true
            let flags = NSEvent.modifierFlags
            dashboard.click(url, mode: flags.contains(.command) ? .toggle : flags.contains(.shift) ? .extend : .replace)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if isDirectory { dashboard.open(url) } else {
                dashboard.click(url, mode: .replace)
                dashboard.requestPreview()
            }
        })
        .contextMenu {
            if !isDirectory {
                Button("Preview") { dashboard.click(url, mode: .replace); dashboard.requestPreview() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sdcard").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No Source").font(.title2)
            Text("Choose an SD card, a folder, or individual photos.").foregroundStyle(.secondary)
            Button("Choose Source…") { Task { await dashboard.chooseSources() } }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("choose-source")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
