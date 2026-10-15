# ADR-0005: Cancel between files; shield the file in flight

Status: accepted

## Context
Imports of thousands of large files need a Cancel. Copies are atomic (staged `.partial`, then moved together with sidecars) and metadata reads (`AVAsset.load`) abort when their task is cancelled, falling back to the file date, which would misfile a video.

## Decision
- The engine checks `Task.isCancelled` **before each file**. Unreached files become `.cancelled(source:)` results; the report counts them (`ImportReport.cancelled`) and the Results Sheet says "Import Cancelled".
- Each file's work runs in an **unstructured task** (`Task { … }.value`), so cancelling the whole import can never reach the file in flight.
- `ImportViewModel.beginImport(using:)` keeps the run task; `cancel()` cancels it and sets `isCancelling` until the run ends.

## Consequences
- Cancel latency = the time to finish one file (a few hundred ms for a large RAW over a UHS-I card); it cannot interrupt a copy mid-file.
- Tests cancel the *import task from outside* (a transferrer/provider holding the task); cancelling "the current task" inside a callback would only cancel the shield.
- Debug-only `-UITestSlowImport` makes an import long enough for a UI test to press Cancel.
