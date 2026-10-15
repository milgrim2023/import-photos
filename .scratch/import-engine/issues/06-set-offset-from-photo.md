# Set time offset from a reference photo

Status: wontfix
Type: HITL

## What to build
"Set from photo…" next to the offset controls: the user picks a photo, types the real local time it was taken, and the app derives the offset (real − camera time) and fills the amount/unit.

## Acceptance criteria
- [ ] Offset computed correctly across minute/hour/day magnitudes and negative values.
- [ ] Result populates `offsetAmount`/`offsetUnit` (choose the largest unit that divides evenly, else minutes).
- [ ] ViewModel-level tests; UX reviewed with the user (HITL).

## Blocked by
- None - can start immediately

## Comments
- 2026-10-15 **Won't fix** (decision by the author): the structured offset control (amount + unit + quick buttons) with the live Preview is sufficient; deriving an offset from a reference photo is not wanted. Closing without implementation.
