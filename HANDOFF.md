# Handoff: ImportPhotos (macOS SD-card photo importer)

Repo: `~/projects/milgrim2023/PhotoImport` (git repo root is two levels up and has **no commits**; nothing here is committed yet).
Start with `README.md` (map + commands), then `CONTEXT.md` (rules/glossary), `.scratch/import-engine/PRD.md` (as-built requirements), `docs/adr/` (decisions). **This document does not repeat those**; it only holds what isn't in them.

## State at handoff (2026-10-15)
- v1.0.0 built and working. `swift test`: **136 tests, 0 failures**; `scripts/ui-tests.sh`: **10 XCUITest smoke tests, 0 failures** (~1 min, needs an unlocked desktop; ADR-0004). Non-UI logic coverage ≈ 88% lines (≥94% everywhere except `FileSelectionService`, the `NSOpenPanel` wrapper).
- Distributable: `scripts/release.sh` → `dist/ImportPhotos-1.0.0.dmg` (ad-hoc signed, arm64 only, ~564 KB; no UI-test code in the release binary). Verified: mounts, installs, launches, restores destination/template.
- Issues 01–05, 07 and 08 are implemented (`Status: ready-for-human` = needs the user's manual check). Issue 06 is **wontfix** (author's decision). **No open tickets.**

## What the user has verified by hand vs. what is only machine-verified
- Hand-verified by the user: picker with files/folders, thumbnail grid, sort (after a fix), Quick Look preview, importing a real ~180-file Sony ARW set and a Ricoh GR DNG card.
- **Now covered by the XCUITest suite** (so no longer "never verified"): click/⌘-click/⇧-click selection (mutation-checked: breaking shift handling fails the test), sort menu reordering, hidden sidecars, import → Results Sheet, duplicate re-import, the orange sidecar warning, offset controls.
- **Still manual / unverified:** the system `NSOpenPanel` (the UI suite uses a fake panel), the Quick Look window, real thumbnail rendering, the Results Sheet *Failed* and *ignored sidecars* sections visually (their text is unit-tested), narrow-window header layout, and the packaged DMG on **another Mac / macOS 14**.

## How the user likes to work
- Strict TDD in vertical slices (red → green, `tdd` skill). Seams were agreed up front: `IngestionEngine.process` end-to-end on temp dirs (S1), `PathTemplater` (S2), `MediaMetadataProvider` (S3), ViewModels (S4). Fakes only at system boundaries.
- Terse "caveman" replies were requested earlier in the session; plain concise prose has been accepted since.
- **No Apple Developer account, none wanted.** Apple Silicon only. Don't suggest notarization/TestFlight.
- Prefers being told what was *not* verified. Say so explicitly.

## Gotchas learned the hard way
- **Sandbox**: picking *individual files* grants access to those files only; sidecars next to them are invisible. Security-scoped bookmarks only resolve in the app that created them, so they can't be seeded from scripts. Folder grants are recursive.
- **Sidecar naming in the wild**: Ricoh/darktable-style `IMG.DNG.xmp` and `IMG.ARW.rrdata` (not just `IMG.xmp`). RAW+JPEG share one `IMG.xmp`. Sidecars have their own mtime, which once filed them in the wrong date folder.
- **Source folder inside the destination** (user imported `~/Pictures/RAW` into `~/Pictures`): every file matched itself as a duplicate. Fixed (a file is never its own duplicate); test `IngestionSourceInsideDestinationTests`.
- **Performance**: engine overhead was quadratic (62 of 64 s on 3,000 files). Fixed; guarded by `IngestionScalingTests` (1,500 files < 5 s). Real throughput is card-bound: the user's SD card is UHS-I (~90 MB/s read, parallel reads don't help, `copyItem` is already optimal).
- SwiftUI `List(children:selection:)` doesn't render selection reliably → custom grid. `Table` worked but was replaced by thumbnails.
- `NSLog` from the sandboxed app wasn't visible in `log show`; for diagnostics write to `FileManager.default.temporaryDirectory` (inside the container) instead.
- UI tests: SwiftUI static text exposes its string in `value` (sometimes `label`); result tiles carry the count in their *label*; identifiers on a row container hide the child text (put them on the Text). `XCUIElement.perform(withKeyModifiers:)` works on macOS. The UI-test runner needed **no** extra permission prompt here, but the terminal still can't script the UI by itself.
- Test paths: macOS temp dirs are `/private/var/...`; `Fixture` uses `realpath` so URL equality holds. `/tmp` vs `/private/tmp` bit the sidecar de-dup (now compares resolved paths).
- Tests that set the persisted `template` must pass an isolated `UserDefaults(suiteName:)` or they pollute later runs.
- `PhotoImport.xcodeproj` is generated; edit `project.yml` + `xcodegen generate`. `PRODUCT_NAME` is "Import Photos" (process name changed from `PhotoImport`).

## Handy debugging tricks
- Screenshots work from the terminal (screen-recording permission granted): `screencapture -x -o -l <windowID> out.png`, get the window id with a tiny Swift `CGWindowListCopyWindowInfo` script. The terminal has **no accessibility permission**, so UI scripting/clicking is not possible; to inspect UI states I temporarily added a DEBUG-only env-var seed and reverted it (don't ship that).
- Benchmark trick: an exFAT `hdiutil` disk image as a fake SD card (but the OS page cache makes copy speed unrealistic).
- Real-data checks used read-only copies of the user's RAW files in `/tmp`; never write into the user's photo folders.

## Suggested next work
No tickets are open. Candidates if the user wants more (none requested):
1. Run the DMG on a second Mac / macOS 14 and tick off the remaining manual checks (open panel, Quick Look, thumbnails).
2. Make the first git commit (decide ignores: `build/`, `dist/`, `.build/`, generated `PhotoImport.xcodeproj`).
3. Design question, decided *no* (ADR-0002): refreshing a changed sidecar on re-import. Don't reintroduce "newer sidecar copied" without asking.
4. Won't do: set offset from a reference photo (issue 06).

## Suggested skills for the next session
- `tdd` — all new behavior (confirm seams first; presentation/ViewModel seam for UI logic, XCUITest only for real interaction).
- `diagnose` — if a real-card import misbehaves (reproduce with read-only copies first).
- `to-issues` / `triage` — to refine and prioritise issues 05–08 (`Status:` labels live in `docs/agents/triage-labels.md`).
- `code-review` — before the first git commit (the repo has none; also decide what to ignore: `build/`, `dist/`, `.build/`, `PhotoImport.xcodeproj`).
- `domain-modeling` — when new terms/decisions appear (update `CONTEXT.md` / add an ADR).
- `caveman` — only if the user asks for terse mode again.

## Not done / loose ends
- No git commits exist. Nothing has been published beyond the local DMG.
- Orphan-sidecar and failure UI strings are reasonable but unreviewed by the user.
- Cancel takes effect after the file in flight (ADR-0005); capture-date sort reads EXIF lazily (issue 07).
- Template tokens are limited to the seven documented ones (`{{YEAR}} … {{NAME}}`); no camera/model token.
