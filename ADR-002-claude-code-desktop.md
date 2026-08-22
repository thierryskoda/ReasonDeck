# ADR-002: Claude Code Desktop adapter

- Status: Accepted, pending authenticated live compatibility verification
- Scope: Claude Code model-and-effort selection in Claude Desktop

## Context

One physical shortcut should carry independent ChatGPT and Claude Code assignments. Claude Desktop also contains non-Code surfaces, so merely checking its bundle identifier is insufficient. Terminal-based Claude Code is outside this decision because safely identifying the active prompt and session across terminals would require a separate integration contract.

Claude Code Desktop documents dedicated model and effort menus at Command-Shift-I and Command-Shift-E. Those commands provide a narrower target than screen geometry, but synthetic input still requires strict context validation and observable final-state verification.

## Decision

1. Store one shortcut chord with optional, independently typed ChatGPT and Claude Code assignments. At least one assignment must remain enabled.
2. Migrate version-1 configuration once into version 2 as ChatGPT-only. If version-2 data exists but is invalid, fail closed and never fall back to version 1.
3. Consume a matching event only when the frontmost application's enabled assignment matches. Capture the target and process at key-down without blocking the event-tap callback, then immediately require that process to remain frontmost and capture its focused-window identity before dispatch.
4. For Claude, require the captured Claude Desktop process and focused window to remain frontmost and require an Accessibility-visible Code surface before every phase.
5. Open Claude Code's model and effort menus with their documented keyboard commands. Mark generated events with ReasonDeck's private event-source value so the global event tap passes them through without matching them again.
6. Select only an exact, enabled Accessibility label from the closed model or effort set. Do not use list position, substring guessing, fixed coordinates, terminal commands, or settings-file edits.
7. Reopen each menu and require the requested item to expose selected state. If that state cannot be observed, report failure even if the click appeared to work.
8. Keep terminal Claude Code integrations out of scope until a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content. Cursor Agent/Chat model switching is covered separately in [ADR-003](ADR-003-cursor-model-picker.md).

## Consequences

- The same shortcut can safely select different profiles depending on which supported app is frontmost.
- Claude UI or Accessibility changes disable the adapter instead of selecting by position.
- A Claude Desktop account entitled to the Code tab is required for live compatibility verification. A Free-account upgrade screen, unit tests, and a signed build do not establish that compatibility by themselves.
- Claude choices can differ by plan or session. A missing exact item is reported as unavailable; ReasonDeck never substitutes a model or effort.

## Supersession condition

Prefer an official local Claude Code model-and-effort API if Anthropic exposes one that preserves active-session scoping and verifiable final state. Revisit terminal support separately when a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content.
