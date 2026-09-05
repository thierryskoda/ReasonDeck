# Changelog

Notable user-facing changes are recorded here. Release artifacts and tags are immutable; a corrected build receives a new version.

## 0.2.6 - 2026-09-05

### Added

- Show each supported app's installed version and local compatibility health in Settings: exact signed-live versions are **Verified**, successful switches on other versions are **Working, unverified**, and picker-contract failures are **Needs update**.
- Recognize Antigravity's exact `Gemini 3.8 Flash` and `Low` labels, plus its exact `Fast`-badged Medium Flash rows without exposing `Fast` as a reasoning effort.

### Fixed

- Stop Antigravity from reporting the requested effort when it actually selected a same-model row with a different effort. ReasonDeck now checks one exact combined row and independently verifies the final model and effort.

### Changed

- Give first-time and newly enabled Antigravity shortcuts combinations exposed by Antigravity 2.8.1. Existing saved shortcuts remain unchanged and unavailable combinations fail without substitution.

### Safety

- Keep version status advisory instead of accepting or rejecting an app by version alone. Every switch still uses the adapter's exact structural preflight and final-state verification, and runtime observations are kept only in memory for the exact app process and version.
- Do not treat permission, focus, configuration, missing-composer, entitlement, or unavailable-model failures as evidence that an app version is incompatible.
- Bind Antigravity's Command-Slash picker, row action, dismissal, and final verification to the originally captured process and window, and read only recognized labels from allowlisted control roles.

## 0.2.5 - 2026-09-05

### Fixed

- Recognize Claude Code's renamed `Model: <name>` title on both the closed composer popup and opened model menu. On Claude Desktop 1.46388.3, ReasonDeck could visibly open the picker, then wait for its obsolete bare title and fail with an accessibility error.
- Initialize Claude's web Accessibility bridge when Claude or ReasonDeck launches, outside shortcut transactions, then discover the already-exposed composer when a shortcut is pressed. This avoids binding a shortcut while Chromium is rebuilding its native window.

### Safety

- Match both version-specific forms as exact full titles paired with an exact closed-set model name, refusing partial or trailing-copy variants and remaining independent of model order.
- Initialize each Claude process at most once and collect no chat content. During switching, never rebind a shortcut to a different window identity; missing-surface preparation remains a fail-closed fallback.

## 0.2.4 - 2026-09-01

### Fixed

- Select Sonnet 5, Opus 5, and other exact supported models directly from Claude Desktop's verified primary Chat/Cowork model menu when Claude exposes them there.
- Open `More models` only when the requested exact model is absent from the primary menu, preserving the bounded fallback for account layouts that still place supported models in the nested menu.

## 0.2.3 - 2026-09-01

### Fixed

- Retry Claude Desktop surface and composer discovery while Chromium finishes publishing its Accessibility tree, preventing transient shortcut failures immediately after focus changes or interface updates.
- Fall back to the freshly verified Chat/Cowork composer geometry when Chromium reports successful Accessibility menu actions but leaves the model picker closed.
- Focus the paid layout's exact `More models` row and open its owned submenu with native Right Arrow, then select the exact verified model-row geometry with empty mouse flags and without the keyboard event tap's sentinel. When Chromium keeps the owned menus open after using the first click only for focus, let its responder settle, then reacquire the exact row before a bounded activation click.

### Safety

- Keep every retry bounded by the existing two-second deadline and revalidate the exact frontmost process and focused window before each Accessibility scan.

## 0.2.2 - 2026-08-31

### Fixed

- Support Claude Desktop's paid Chat and Cowork model menu, including exact Fable 5, Opus 5, paid Medium/High defaults, and paid Max usage-copy variants.
- Open Chat/Cowork's nested effort menu through the exact verified row geometry when Chromium advertises an `AXPress` action that only focuses the row.
- Recognize Claude's selected Code tab when Accessibility exposes radio value `1` instead of `AXSelected`.
- Replace Claude Code's obsolete keyboard-menu path with its current exact model popup and five-step effort slider.

### Safety

- Bind Claude Code switching to one visible Prompt composer and its structurally related model and effort controls.
- Require the Code effort slider's numeric value and exact description to agree at every bounded step, then verify the closed composer state.
- Preserve frontmost-process and focused-window revalidation before every Accessibility, pointer, and slider action.

## 0.2.1 - 2026-08-31

### Fixed

- Recognize Claude Desktop Home/Chat's exact `Max 3.5× or more usage` effort row and final composer title while retaining the previously accepted exact `Max` label.
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
