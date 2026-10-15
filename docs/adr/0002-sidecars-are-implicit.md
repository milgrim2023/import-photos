# ADR-0002: Sidecars are implicit, hidden, and never overwrite

Status: accepted

## Context
Photos come with companion files (`IMG.xmp`, `IMG.ARW.xmp`, `.rrdata`). Treating them as ordinary files produced misfiled sidecars (their own mtime picked a different date folder), inflated counts, aborted imports when RAW+JPEG shared one `.xmp`, and risked replacing user-edited sidecars.

## Decision
1. Sidecars are **never shown or selected** in the UI.
2. They are copied **implicitly** with their photo, into the photo's folder under its final (possibly renamed) name, and only **counted** in the results.
3. **Orphans are never imported**; they are listed in the results as ignored.
4. A sidecar already in the destination is **never replaced or duplicated** (a RAW+JPEG pair shares one). A photo skipped as a duplicate never brings its sidecar.
5. Both naming styles are supported (`IMG.xmp`, `IMG.ARW.xmp`). Extensions are a single set in `SidecarNaming.extensions` covering the common tools (Adobe/darktable xmp, RawTherapee, ART, DxO, Capture One, Canon DPP, Apple, ON1, UFRaw, Exiv2/ExifTool, …); generic types (`xml`, `json`, `txt`) and playable proxies (`lrv`) are excluded on purpose.
6. Failures are **per file**; a failed photo leaves no partial photo or sidecar behind.

## Consequences
- Editing a sidecar on the card and re-importing does **not** refresh the destination copy (by design).
- Individually picked photos can't reveal their sidecars in the sandbox; the UI warns, and a picked sidecar is paired with its picked photo.
