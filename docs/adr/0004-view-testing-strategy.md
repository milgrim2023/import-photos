# ADR-0004: Test views via presentation types + an XCUITest smoke suite

Status: accepted

## Context
SwiftUI views had no automated tests. Gesture bugs (shift-click lost behind a double-click delay) and layout/identifier slips only showed up by hand.

## Decision
1. **Humble views.** Anything a view *decides* (summary text, enabled states, which result sections/notes appear, labels) lives in plain types: `BottomBarPresentation`, `ResultsPresentation` (`Presentation.swift`) and `DashboardViewModel` / `ImportViewModel` (`offsetLabel`, `destinationLabel`, `browserTitle`, `canPreview`, `ImportViewModel.start(using:)`). They are unit-tested with `swift test`.
2. **XCUITest smoke suite** (`UITests/`, 8 tests, ~1 min, `scripts/ui-tests.sh`) drives the real app through the accessibility tree: selection gestures (click / ⌘ / ⇧), sort menu, import → results sheet, duplicate re-import, sidecar warning, offset controls.
3. **Debug-only test mode** (`App/UITestSupport.swift`, `#if DEBUG`, launch args `-UITesting`, `-UITestPickFiles`, `-UITestCannotListFolders`): fake open panel, fixture photos created *inside the app's container* (the sandbox can't read the runner's temp), throwaway `UserDefaults`. Compiled out of Release (verified: no test strings in the release binary).
4. Views expose stable `accessibilityIdentifier`s (`cell-<name>`, `import-button`, `results-title`, `stat-<title>`, …); grid cells are accessibility buttons with a "selected"/"not selected" value; result tiles put the count in the label ("4 Photos imported").

## Consequences
- The system `NSOpenPanel`, Quick Look and thumbnail rendering are still manual checks (out-of-process / not in the accessibility tree).
- UI tests need an unlocked desktop session; they are not part of `swift test` or `scripts/release.sh`.
- When adding UI: put decisions in a presentation type with a unit test, add identifiers, extend the smoke suite only for interaction that can't be unit-tested.
- SwiftUI static text exposes its string via `value` (sometimes `label`); use the `text(_:)` helper in the UI tests.
