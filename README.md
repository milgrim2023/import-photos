# ImportPhotos

macOS (Apple Silicon, macOS 14+) app that **copies** photos/videos from an SD card or folder into a date-organised folder, with de-duplication, a time-offset fix, and sidecar handling. v1.0.0.

## Where things are
| What | Where |
|---|---|
| **Handoff / where to resume** | `HANDOFF.md` |
| Product requirements (as built) | `.scratch/import-engine/PRD.md` |
| Issues (local markdown tracker) | `.scratch/import-engine/issues/` |
| Domain vocabulary & rules | `CONTEXT.md` |
| Decisions | `docs/adr/` |
| Logic + views (SwiftPM library) | `Sources/ImportPhotos/` (`UI/` = SwiftUI views) |
| App host target, entitlements | `App/` ; project generated from `project.yml` |
| Unit tests | `Tests/ImportPhotosTests/` (`TestSupport.swift` = fixtures) |
| UI smoke tests (XCUITest) | `UITests/`, test mode in `App/UITestSupport.swift` (Debug only) |
| Release packaging | `scripts/release.sh`, `scripts/FRIENDS-READ-ME.txt`, `scripts/make-icon.swift` |

## Commands
```bash
swift test                                   # logic, view-model and presentation tests (real temp-dir filesystem)
scripts/ui-tests.sh                          # 10 XCUITest smoke tests driving the real app (~1 min, needs an unlocked desktop)
xcodegen generate                            # regenerate PhotoImport.xcodeproj after editing project.yml
open PhotoImport.xcodeproj                   # run the app (sandboxed, ad-hoc signed)
scripts/release.sh                           # tests + arm64 Release build + dist/ImportPhotos-<version>.dmg
swift test --enable-code-coverage            # then: xcrun llvm-cov report <xctest binary> -instr-profile=.build/out/Products/Debug/codecov/default.profdata
```
`xcodegen` is installed via Homebrew. The generated `.xcodeproj` is derived from `project.yml`.

## Architecture in one paragraph
`RealIngestionEngine` orchestrates small protocol-backed collaborators (metadata provider, path templater, collision judge, media transferrer). `DashboardViewModel` / `ImportViewModel` hold all UI logic and are fully unit-tested; the SwiftUI views are thin. Views only render `Presentation` types and view-model state (ADR-0004). System boundaries (open panel, bookmarks, QuickLook) are the only things faked in unit tests; the UI suite uses a Debug-only fake panel and fixture photos.
