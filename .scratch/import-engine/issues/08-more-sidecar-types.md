# Recognise more sidecar types

Status: ready-for-human
Type: AFK

## What to build
`SidecarNaming.extensions` held only `xmp` and `rrdata`. Add the per-photo companion files written by other common tools, whether or not the user uses them.

## Acceptance criteria
- [x] Extensions added to the single set in `SidecarNaming.swift`: `pp3 pp2 arp` (RawTherapee, ART), `dop` (DxO), `cos` (Capture One), `vrd dr4` (Canon DPP), `thm` (Canon/GoPro video thumbnail), `aae` (Apple Photos), `on1` (ON1), `ufraw`, `exv mie` (Exiv2/ExifTool), plus the existing `xmp rrdata`.
- [x] Both naming styles (`IMG.ext`, `IMG.ARW.ext`) travel with the photo for **every** supported extension (test uses an independent literal list).
- [x] Upper-case extensions recognised (`MVI_0001.THM`).
- [x] Generic/playable look-alikes (`xml json txt lrv mp4 mov jpg`) stay ordinary importable files (test).
- [x] Sidecars from these tools are hidden in the grid (test).

## Blocked by
- None

## Comments
- 2026-10-15 Deliberately **not** included: `xml` (Sony video XML lives in a separate folder and is also a normal file type), `json` (e.g. Google Takeout; too generic), `txt`, `lrv` (a playable GoPro proxy video), and Premiere cache files (`pek`, `cfa`). Add them to `SidecarNaming.extensions` if a real workflow needs them; an orphan is ignored (never imported), so be careful with generic types.
- Extensions I was less than certain are written *next to* the photo (rather than in a subfolder): `cos` (Capture One normally keeps settings in a `CaptureOne/` subfolder), `dr4`, `on1`. They are harmless if absent.
