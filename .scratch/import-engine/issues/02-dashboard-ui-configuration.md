# Dashboard UI & Configuration

Status: ready-for-human
Type: AFK

## What to build

Build the main dashboard interface, including the source file browser (supporting recursive directory inspection) and the configuration inspector for the destination, template, and time offset.

## Acceptance criteria

- [x] Display a source file browser that allows recursive directory selection.
- [x] Display a configuration inspector for destination, template string, and time offset.
- [x] UI updates correctly when selection or configuration changes.

## Blocked by

- .scratch/import-engine/issues/01-macos-file-access-persistence.md

## Comments

- ViewModel behavior covered by tests (`DashboardViewModelTests`, `ImportViewModelTests`). SwiftUI views compile and app target builds (`xcodebuild`), but the GUI has not been run by hand. Manual check needed.

- 2026-10-15 **As built differs from the original text**: instead of a tree, the left pane is a thumbnail grid (see PRD §3.1, ADR-0001); the right pane holds Destination / Template / Time Offset (structured amount+unit, live Preview). Template is persisted; offset resets each launch. Sidecars hidden (ADR-0002). Sorting added (date default).
