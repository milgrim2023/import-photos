# Cancel a running import

Status: ready-for-human
Type: AFK

## What to build
A Cancel button on the bottom bar while an import runs. Cancelling stops after the current file finishes (a file is never left half-copied), keeps what was already imported, and shows the Results Sheet for what completed.

## Acceptance criteria
- [x] Cancel is visible and enabled only while importing; shows "Cancelling…" (disabled) once pressed (`BottomBarPresentation`, UI test).
- [x] The engine honours cancellation between files and reports files not reached as `.cancelled` (`IngestionCancellationTests`).
- [x] No `.partial` files remain after a cancel; the in-flight file completes with its sidecars.
- [x] Cancellation never reaches the in-flight file (it runs in an unstructured task), so a video's metadata read can't be aborted and the file misfiled (`IngestionCancellationShieldTests`).
- [x] ViewModel: `beginImport(using:)` / `cancel()` / `isCancelling` (`ImportViewModelCancelTests`); report has `cancelledCount`, title "Import Cancelled" and a note "N photos were not imported because the import was cancelled."
- [x] End to end in the real app: `testCancelMidImportKeepsFinishedFilesAndReportsTheRest` (Debug-only `-UITestSlowImport`).

## Blocked by
- None

## Comments
- 2026-10-15 Cancel takes effect after the file in flight (a 30 MB RAW can take a few hundred ms). It cannot interrupt a file mid-copy by design (atomic intent, ADR-0002/0005).
