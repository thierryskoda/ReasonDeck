# Changelog

Notable user-facing changes are recorded here. Release artifacts and tags are immutable; a corrected build receives a new version.

## 0.1.0 - 2026-08-06

### Added

- Establish ReasonDeck as the public product, bundle, and release identity.
- Create, edit, and delete any number of model-and-reasoning keyboard shortcuts.
- Start with no default shortcuts and configure each keyboard command in Settings.
- Show Accessibility and Input Monitoring readiness directly in Settings.
- Guide builds opened outside `/Applications` through a safe install-and-relaunch step before requesting permissions.
- Keep shortcuts scoped to frontmost ChatGPT and pass unrelated key events through.
- Provide a fail-closed Developer ID, notarization, DMG, and checksum release command.

### Changed

- Open the matching macOS privacy pane from one clear permission action, then recheck permissions and retry hotkeys automatically when ReasonDeck becomes active again.
- Tighten the Settings layout and permission-row alignment while preserving native macOS controls.

### Safety

- Verify model and reasoning titles after selection.
- Keep the app local-only with no chat-content collection or network implementation.
