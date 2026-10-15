# Sort by EXIF capture date

Status: ready-for-human
Type: AFK

## What to build
The date sort uses the file modification date (cheap). Add "Capture date" sorts that read EXIF/video metadata lazily and cache it, without slowing down large folders.

## Acceptance criteria
- [x] New `FileSortOrder` cases "Capture date (oldest first)" and "(newest first)"; folders still first.
- [x] Metadata read lazily, only for the files shown and never for hidden sidecars, once per file per session, a few at a time and in chunks so the grid re-sorts progressively (`loadCaptureDates`).
- [x] Choosing the sort never blocks: until a file's capture date arrives it is ordered by file date.
- [x] Works for picked files and for subfolders; other sort orders never read metadata.
- [x] Tests: files whose modification dates disagree with their EXIF dates sort by EXIF; each file read exactly once; 300 photos load < 5 s; UI test `testCaptureDateSortIsAvailableAndOrdersTheGrid`.
- [x] A small spinner next to the Sort menu while dates load.

## Blocked by
- None

## Comments
- 2026-10-15 Unreadable files cache their file date (no retry loops). A load cancelled mid-way (folder changed) never caches fallbacks.
- Design and trade-offs: `docs/adr/0006-lazy-capture-date-sorting.md`.
