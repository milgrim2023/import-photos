# ADR-0001: Embedded thumbnail browser; the system panel is the access grant

Status: accepted

## Context
The app is sandboxed. It can only read folders the user explicitly grants through the system open panel, and keeps that access across launches via security-scoped bookmarks. A custom browser can't list `/Volumes` or arbitrary folders without a grant. Users also want to pick *individual files*, see thumbnails, and use Finder-style selection.

## Decision
- "Choose Source…" opens `NSOpenPanel` (files + folders, multiple). That panel is the **access grant**; its results are persisted as bookmarks (`bookmarks_selected_sources`, `bookmark_selected_destination`).
- Browsing and selecting happens in an **embedded SwiftUI thumbnail grid** inside the granted folder. Selection semantics live in `DashboardViewModel` (click/⌘/⇧/select-all), tested without UI.
- Picking one folder = browse it; picking files/several items = import those, pre-selected.

## Consequences
- Individually picked files grant access to only those files, so their sidecars are unreachable unless picked too → warning banner (ADR-0002).
- Restored bookmarks must call `startAccessingSecurityScopedResource`; missing folders fail to resolve and are dropped silently.
- SwiftUI's hierarchical `List(children:selection:)` didn't render selection reliably, hence a custom grid.
- Security-scoped bookmarks resolve only in the app (signing identity/bundle) that created them: they can't be pre-seeded from scripts.
