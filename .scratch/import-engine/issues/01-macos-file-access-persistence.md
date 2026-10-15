# macOS File Access & Persistence

Status: ready-for-human
Type: HITL

## What to build

Implement the mechanics of selecting source volumes/directories and destination folders using macOS file pickers, and persisting access via Security-Scoped Bookmarks to satisfy macOS Sandbox requirements and maintain access across sessions.

## Acceptance criteria

- [x] User can select a source volume or sub-directory.
- [x] User can select a destination folder.
- [x] Selected paths are persisted using Security-Scoped Bookmarks.
- [x] App can re-access previously selected paths on next launch (startAccessingSecurityScopedResource + stale refresh in `RealSecurityBookmarkManager`; entitlements in `App/PhotoImport.entitlements`).

## Blocked by

- None - can start immediately

## Comments

- Unit-tested: bookmark save/load round trip, persist/restore. NOT verified: behavior under a real sandboxed, signed build and removable volumes. Manual check needed.

- 2026-10-15: restore works for destination/sources across rebuilds (list of sources, multi-select panel, files + folders). A source that no longer exists is silently not restored. See ADR-0001.
