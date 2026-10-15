# Active Import & Status Bar

Status: ready-for-human
Type: AFK

## What to build

Implement the logic to trigger the ingestion process from the UI, displaying a persistent status bar that shows real-time progress (percentage-based) and the name of the file currently being processed.

## Acceptance criteria

- [x] User can trigger the ingestion process from the UI.
- [x] A prominent status bar displays progress (percentage) during import.
- [x] The status bar shows the name of the file currently being processed.

## Blocked by

- .scratch/import-engine/issues/02-dashboard-ui-configuration.md

## Comments

- ViewModel behavior covered by tests (`DashboardViewModelTests`, `ImportViewModelTests`). SwiftUI views compile and app target builds (`xcodebuild`), but the GUI has not been run by hand. Manual check needed.

- 2026-10-15 Progress is an always-visible bottom bar (idle: selection count + Import; running: progress, %, current file). Engine overhead made linear; copy speed is card-bound (~90 MB/s on a UHS-I card).
