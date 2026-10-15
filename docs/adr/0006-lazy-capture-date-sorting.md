# ADR-0006: Capture-date sorting is lazy, cached and never blocks the grid

Status: accepted

## Context
Sorting by *capture date* (EXIF / video creation date) needs metadata from inside each file, unlike the file modification date, which comes free with the directory listing. On an SD card (~90 MB/s, UHS-I) every metadata read is real I/O, and cards hold hundreds to thousands of files. `DashboardViewModel.items` is a synchronous computed property that SwiftUI re-evaluates often, so it cannot wait on I/O.

## Alternatives considered
1. **Read every file's metadata when a source is chosen.** Simple, but delays the first grid and wastes I/O for users who never use this sort.
2. **Make `items` async / sort in the view.** Spreads async state through every consumer (selection ranges, preview list, Select All) that relies on a single ordered `items`.
3. **Persist capture dates on disk.** Survives relaunch, but needs invalidation (files change, cards are swapped) for little benefit; a session cache is enough.

## Decision
- Choosing a capture-date order reads **nothing by itself**. `items` stays synchronous and orders files by `captureDates[url] ?? file date`, so the grid is instant and simply re-sorts as dates arrive.
- `DashboardViewModel.loadCaptureDates()` fills a **session cache** (`captureDates: [URL: Date]`) for the files currently shown only: current folder (or the picked items), photos only, **never hidden sidecars or folders**. It does nothing for other sort orders.
- Reads are **chunked** (48 files) with **bounded concurrency** (8 at a time); results are published per chunk so the grid re-sorts progressively. `isLoadingCaptureDates` drives a small spinner.
- Each file is read **at most once per session**. An unreadable file caches its file date so it is not retried forever, but a load that was **cancelled** (user changed folder/sort) never caches fallbacks, only successful reads.
- The view re-triggers loading with `.task(id: sort + folder + roots)`; SwiftUI cancels the previous load automatically.
- Metadata comes from the same `MediaMetadataProvider` the importer uses, so the sort order and the import's date logic agree (EXIF, then video creation date, then file date).

## Consequences
- The first view of a capture-date-sorted folder briefly shows file-date order, then settles. Acceptable and documented in the UI behaviour (spinner).
- Memory cost is one `Date` per visited file for the session.
- Capture dates are **unshifted**: the sort ignores the time offset (it orders the camera's own clock).
- Tests (`CaptureDateSortTests`): ordering with files whose file dates disagree with EXIF, no read on choosing the sort, folders on top and sidecars never read, each file read once, other sorts read nothing, subfolders and picked files, and 300 files < 5 s.
- Related: ADR-0001 (grid), ADR-0004 (testing approach), issue 07.
