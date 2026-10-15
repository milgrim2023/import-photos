## Agent skills

### Issue tracker

Issues are tracked as markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout (one `CONTEXT.md` + `docs/adr/` at root). See `docs/agents/domain.md`.

## Working in this repo
- Start with `README.md` (map + commands) and `CONTEXT.md` (rules). Tests first (`tdd` skill): `swift test`.
- Don't edit `PhotoImport.xcodeproj` by hand; edit `project.yml` and run `xcodegen generate`.
- Builds are Apple-Silicon only; don't add Intel architectures.
- UI changes: put decisions in a presentation type/view model with a unit test (ADR-0004), give controls an `accessibilityIdentifier`, and run `scripts/ui-tests.sh` (needs an unlocked desktop).
