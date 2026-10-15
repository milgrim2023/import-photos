# Import Completion & Results Sheet

Status: ready-for-human
Type: AFK

## What to build

Implement the final reporting step, which displays a modal Results Sheet containing the statistical summary (total imported, skipped, renamed) and the itemized lists of every file that was skipped or renamed.

## Acceptance criteria

- [x] Upon completion, a modal Results Sheet is displayed.
- [x] The sheet displays statistics: total files successfully imported, duplicates skipped, and files renamed.
- [x] The sheet provides itemized lists of every file that was skipped or renamed.

## Blocked by

- .scratch/import-engine/issues/03-active-import-status-bar.md

## Comments

- ViewModel behavior covered by tests (`DashboardViewModelTests`, `ImportViewModelTests`). SwiftUI views compile and app target builds (`xcodebuild`), but the GUI has not been run by hand. Manual check needed.

- 2026-10-15 Results sheet also shows Failed (with reasons), sidecars copied (count) and ignored orphan sidecars. Failures are per file. See ADR-0002.
