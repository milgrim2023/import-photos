# ADR-0003: Ad-hoc signed, Apple-Silicon-only DMG

Status: accepted

## Context
The app is for the author and a few friends. No paid Apple Developer account (so no Developer ID signing or notarization) and no wish to get one.

## Decision
- `scripts/release.sh` builds a Release app with an **ad-hoc signature**, **arm64 only** (`ARCHS=arm64`, `EXCLUDED_ARCHS=x86_64`; the script fails if any other slice appears), and packages a DMG containing the app, an Applications shortcut and `READ ME FIRST.txt`.
- No `get-task-allow` entitlement in shared builds (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`).

## Consequences
- First launch on a friend's Mac needs the one-time "Open Anyway" (macOS 15+) / right-click Open (macOS 14) step, and again for each new downloaded version.
- Intel Macs are unsupported.
- Bookmarks are tied to the signing identity; they survived rebuilds in testing, but after an update users may need to re-pick folders (stated in the READ ME).
