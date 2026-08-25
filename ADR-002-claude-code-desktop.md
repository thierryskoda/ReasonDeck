# ADR-002: Claude Desktop adapter

- Status: Accepted and runtime-enabled; Home/Chat verified on Claude Desktop 1.34493.1, paid Code-session verification pending
- Scope: Claude Desktop Home/Chat and Claude Code model-and-effort selection

## Context

One physical shortcut should carry independent ChatGPT and Claude Desktop assignments. Claude Desktop exposes a combined model-and-effort picker in the Home/Chat composer, while paid accounts also expose separate Claude Code menus. Merely checking the bundle identifier is insufficient. Terminal-based Claude Code is outside this decision because safely identifying the active prompt and session across terminals would require a separate integration contract.

Claude Code Desktop documents dedicated model and effort menus at Command-Shift-I and Command-Shift-E. Those commands provide a narrower target than screen geometry, but synthetic input still requires strict context validation and observable final-state verification.

## Decision

1. Store one shortcut chord with optional, independently typed ChatGPT and Claude Desktop assignments. Keep the persisted `claudeCode` field for configuration compatibility. At least one assignment must remain enabled.
2. Migrate version-1 configuration once into version 2 as ChatGPT-only. If version-2 data exists but is invalid, fail closed and never fall back to version 1.
3. Consume a matching event only when the frontmost application's enabled assignment matches. Capture the target and process at key-down without blocking the event-tap callback, then immediately require that process to remain frontmost and capture its focused-window identity before dispatch.
4. For Claude, require the captured Claude Desktop process and focused window to remain frontmost before every phase. Select one of two mutually exclusive verified surfaces: one exact prompt field with one structurally related combined model popup, or a selected Code tab. Claude 1.34493.1 does not expose the visible Chat selection through raw macOS Accessibility, so that visual radio state is not used as an authorization signal.
5. On Home/Chat, open the exact combined popup, require an owned menu with at least two closed-set model rows, and reject rows that expose upgrade-only labels. Open the exact effort submenu from the verified model menu and require at least three closed-set effort rows. Claude's Chromium submenu requires an exact effort-row AXPress followed by a validated focused Right Arrow; refresh the owned menu after its bounded settle period before using any row reference.
6. Prefer direct Accessibility actions. A frame-derived HID click is permitted only for the structurally verified composer popup or an exact row inside its verified owned menu. Focused HID key delivery is permitted only for an already verified nested menu that ignores PID-targeted keys. Revalidate the captured process/window immediately before delivery, constrain click points to current menu geometry, and restore the pointer afterward.
7. On Code, open the model and effort menus with their documented keyboard commands. Mark generated events with ReasonDeck's private event-source value so the global event tap passes them through without matching them again.
8. Select only exact labels from closed source sets. Do not use list position, substring guessing, fixed screen coordinates, terminal commands, or settings-file edits. Verify Home/Chat through the combined composer title and Code through selected item state; report failure even when an input appeared to work.
9. Keep terminal Claude Code integrations out of scope until a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content. Cursor Agent/Chat model switching is covered separately in [ADR-003](ADR-003-cursor-model-picker.md).

## Consequences

- The same shortcut can safely select different profiles depending on which supported app is frontmost.
- Claude UI or Accessibility changes disable the adapter instead of selecting by position.
- A signed Release build passed live Home/Chat switching in Claude Desktop 1.34493.1 on a Free account: Sonnet 5 Medium to High and back, an already-applied Medium run, and a Sonnet-to-Haiku-to-Sonnet model round trip. Haiku selected successfully as `Model: Haiku 4.5 Extended`, then truthfully reported the standard Medium effort as unavailable.
- A Claude Desktop account entitled to the Code tab is still required to verify the separate Code keyboard-menu path. Home/Chat evidence does not establish Code compatibility.
- Claude choices can differ by plan or session. A missing exact item is reported as unavailable; ReasonDeck never substitutes a model or effort.

## Supersession condition

Prefer an official local Claude Code model-and-effort API if Anthropic exposes one that preserves active-session scoping and verifiable final state. Revisit terminal support separately when a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content.
