# Changelog

Notable user-facing changes are recorded here. Release artifacts and tags are immutable; a corrected build receives a new version.

## 0.2.1 - 2026-08-31

### Fixed

- Recognize Claude Desktop Home/Chat's exact `Max 3.5× or more usage` effort row while retaining the previously accepted exact `Max` label.
- Give new installations and newly enabled Claude assignments verified Sonnet 5 Medium/High defaults instead of leaving Claude off or defaulting to an upgrade-only model. Existing saved shortcuts remain unchanged.

## 0.2.0 - 2026-08-31

### Added

- Add exact model-and-effort switching for Claude Desktop Home/Chat, Cursor Agent/Chat, and Antigravity alongside ChatGPT.
- Add a Cursor-only **Next finished session** shortcut that advances only when finished-waiting state is observable.
- Seed new installations with editable economical and premium shortcuts; existing saved configurations remain unchanged.

### Changed

- Report Input Monitoring as granted only when macOS confirms that specific privacy permission; a listener created with Accessibility alone no longer produces a false-ready status.
- Keep slow Accessibility window discovery outside the global hotkey callback so macOS does not intermittently disable the shortcut listener.
- Split model switching into independent ChatGPT, Cursor, Claude Code, and Cursor-navigation adapter transactions behind one typed dispatcher.
- Rebuild ChatGPT switching as an atomic composer-bound transaction with a fresh snapshot after each UI mutation.
- Rebuild Cursor model switching as one verified transaction over the exact frontmost process and focused window.
- Anchor Cursor discovery to the active composer and its owned two-stage parameters/model menus.
- Add exact Grok 4.6 support while retaining Grok 4.5 for older Cursor catalogs.
- Restore the exact previously focused ChatGPT composer after a model shortcut completes.
- Keep the native ChatGPT picker open between verified phases so an effort-only shortcut does not reselect the current model.

### Safety

- Restrict ChatGPT geometry delivery to one snapshot-bound framed composer control; remove the legacy cross-phase picker cache and broad group-offset fallback.
- Scope ChatGPT Model/Effort choices to one visible owned menu root and remove synthetic Escape cleanup from that adapter.
- Revalidate target context before every Accessibility, key, and geometry-derived action; abort on focus or window drift.
- Resolve Electron label/action splits inside one bounded structural row and verify the final model and effort by reopening the owned menu.
- Keep action targets coupled to the AX snapshot that produced them, and wait for Cursor's post-selection composer state to stabilize before reopening parameters.
- Keep Cursor editor and transcript values outside Accessibility reads and logs.

### Known limitations

- Claude Desktop Home/Chat is supported. The separate paid Code-tab path remains experimental until it passes its own signed live switch.
- Cursor and Antigravity expose server-driven labels; ReasonDeck changes nothing when an exact typed model, effort, or finished-session state is unavailable.

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
