# Product Requirements Document: ImportPhotos

Status: **v1.0.0 built** (last updated 2026-10-15). Sections describe the product *as built*; items still open are in §7.
Implementation issues: `.scratch/import-engine/issues/`. Domain vocabulary: `CONTEXT.md`. Decisions: `docs/adr/`.

## 1. Overview
**ImportPhotos** is a macOS-native utility for high-integrity media ingestion. It lets users curate a subset of files from an SD card and copy them into a structured local directory based on a time-sensitive template. It only ever **copies**: nothing on the source is moved or deleted.

## 2. User Stories
- **The Photographer**: "I want to plug in my SD card, pick out the specific photos I want to keep, and have them organized instantly without worrying about duplicates."
- **The Organizer**: "I want to define exactly how my folders look using a template, and if my camera's clock was wrong, I want to fix the folder structure with a time offset."
- **The Safe Keeper**: "I want to know that if I've already imported a photo, the app won't create a second copy, even if I'm applying a time offset."

## 3. Functional Requirements

### 3.1 File Selection & Access
- **Choosing a source**: the system open panel accepts folders, a whole volume, or individual files (multiple selection). Picking **one folder** means "browse this"; picking **files or several items** means "import these" (they are pre-selected).
- **Browsing**: an embedded **thumbnail grid** (QuickLook thumbnails, incl. RAW/video). Folders first, then files; sortable by file date (default, oldest first), file date (newest first), **capture date** (EXIF/video, oldest/newest first; read lazily, cached, falls back to file date until loaded; ADR-0006) or name. Finder-style selection: click, ⌘-click, ⇧-click range, ⌘A / "Select All". Double-click opens a folder; Back goes up.
- **Selection semantics**: nothing selected → Import disabled. A selected folder is imported recursively.
- **Preview**: Space, double-click on a file, the Preview button or context menu opens the system Quick Look panel (steps through the folder's files with the arrow keys).
- **Filesystem access**: Security-Scoped Bookmarks persist the chosen sources and destination across launches (sandboxed app). A saved source that no longer exists (ejected card, deleted folder) simply isn't restored. See ADR-0001.

### 3.2 De-duplication Engine
- **Match logic**: a file is a duplicate if **Name**, **Timestamp** and **File Size** match an existing file anywhere in the destination tree. The timestamp compared is the **offset-adjusted** incoming timestamp against the destination file's stored timestamp (destination files are assumed already corrected).
- **A file is never a duplicate of itself**: importing a source folder that lives inside the destination works.
- **Timestamp priority**: EXIF/metadata capture date (ImageIO for images/RAW, AVFoundation for video); fallback to file modification date.
- **Collision handling**: same name but not a duplicate → numbered suffix (`IMG_0001_1.JPG`, `_2`, …); reported in the results as *Renamed*.

### 3.3 Organization & Time Correction
- **Template**: user-editable string, remembered across launches, default `{{YEAR}}/{{MONTH}}/{{NAME}}`. Tokens: `{{YEAR}} {{MONTH}} {{DAY}} {{HOUR}} {{MINUTE}} {{SECOND}} {{NAME}}` (zero-padded). Unknown tokens are left as typed.
- **Time offset**: a signed amount + unit (minutes / hours / days) with quick buttons (−1 h, +1 h, Reset). Applied to the timestamp **before** both path calculation and the duplicate check. Not persisted (resets each launch). A live **Preview** shows the first selected photo's camera time, corrected time and destination path.
- **Media coverage**: images incl. RAW (`.ARW`, `.DNG`, `.CR2`, `.NEF`…), video (`.MP4`, `.MOV`). Any file type is imported (types without metadata use the file date).
- **Sidecars** (see `CONTEXT.md` / ADR-0002): per-photo companion files from common tools (`xmp rrdata pp3 pp2 arp dop cos vrd dr4 thm aae on1 ufraw exv mie`), named `IMG.xmp` or `IMG.ARW.xmp`. Never shown, copied implicitly with their photo into the photo's folder and final name, never imported alone, and an existing destination sidecar always wins.

### 3.4 Post-Import Reporting
A modal **Results Sheet** shows: photos imported, skipped (duplicates), renamed, **failed** (with reason), a note of **sidecars copied**, a list of **ignored orphan sidecars**, and (after a cancel) a title "Import Cancelled" with how many photos were not imported. Skipped, renamed and failed files are itemized.

## 4. Non-Functional Requirements

### 4.1 Performance & Responsiveness
- **Asynchronous transfers**: the UI stays responsive; the engine runs off the main actor.
- **Progress**: an always-visible bottom bar shows percentage and the current file while importing.
- **Cancel**: a Cancel button while importing stops after the file in flight (never half-copied); finished files are kept and files not reached are reported as not imported (ADR-0005).
- **Engine overhead is O(files)**: sidecar discovery lists each source folder once, destination duplicates are looked up by name and read lazily. (A 3,000-file card folder once spent 62 s of a 64 s import in overhead; now ~0.2 s.) Real copy speed is bounded by the card: the tested UHS-I card reads ~90 MB/s regardless of block size or parallelism.

### 4.2 Security & Integrity
- **Sandbox**: App Sandbox with user-selected read-write and app-scope bookmarks only. No network.
- **Atomic intent**: a photo and its sidecars are staged as hidden `.partial` files and moved into place together; on any failure nothing is left behind.
- **Failures are per file**: an unreadable/uncopyable file is reported as *Failed* and the rest of the import continues.

## 5. User Interface
Single window:
- **Left**: source browser (thumbnail grid, header with Back / path / Sort / Preview / Select All / Change…). Empty state offers *Choose Source…*.
- **Right**: Destination (path + Choose…), Template, Time Offset, live Preview.
- **Bottom bar** (always visible): idle → "N items selected" + **Import**; running → progress bar, %, current file, **Cancel**. Orange banner above it when individually picked photos may have unreachable sidecars (sandbox; see ADR-0002).
- **Results Sheet**: see §3.4.

## 6. Distribution
Ad-hoc signed, **Apple Silicon only** (arm64, macOS 14+) DMG built by `scripts/release.sh`; no Apple Developer account. First launch needs the one-time "Open Anyway" approval. See ADR-0003 and `scripts/FRIENDS-READ-ME.txt`.

## 7. Open / Future
No open tickets. Closed without implementation: *set offset from a reference photo* (issue 06, won't fix).
- Notarized distribution (would need a paid Apple Developer account; not wanted).
- Remaining manual checks: system open panel, Quick Look window, thumbnail rendering, first-open on another Mac. Everything else in the UI is covered by presentation unit tests and the XCUITest smoke suite (ADR-0004).
