# ADR-002: Claude Desktop adapter

- Status: Accepted and runtime-enabled; Chat, Cowork, and Code verified on Claude Desktop 1.40609.0 with a paid account
- Scope: Claude Desktop Chat, Cowork, and Code model-and-effort selection

## Context

One physical shortcut should carry independent ChatGPT and Claude Desktop assignments. Claude Desktop exposes a combined model-and-effort picker in the Chat and Cowork composer, while paid accounts also expose separate Code composer controls. Merely checking the bundle identifier is insufficient. Terminal-based Claude Code is outside this decision because safely identifying the active prompt and session across terminals would require a separate integration contract.

The current paid Code surface exposes an exact model popup and a named effort slider. The previously documented Command-Shift-I and Command-Shift-E path no longer opens those controls in Claude Desktop 1.40609.0, so retaining it would produce a fail-closed but unusable adapter.

## Decision

1. Store one shortcut chord with optional, independently typed ChatGPT and Claude Desktop assignments. Keep the persisted `claudeCode` field for configuration compatibility. At least one assignment must remain enabled.
2. Migrate version-1 configuration once into version 2 as ChatGPT-only. If version-2 data exists but is invalid, fail closed and never fall back to version 1.
3. Consume a matching event only when the frontmost application's enabled assignment matches. Capture the target and process at key-down without blocking the event-tap callback, then immediately require that process to remain frontmost and capture its focused-window identity before dispatch.
4. For Claude, require the captured Claude Desktop process and focused window to remain frontmost before every phase. Select one of two mutually exclusive verified surfaces: one exact Chat/Cowork prompt field with one structurally related combined model popup, or a selected Code radio plus one exact Prompt field and structurally related model and effort popups. Accept Code's selected radio only through role-specific persistent state, including numeric value `1`; never infer it from appearance.
5. On Chat/Cowork, open the exact combined popup and require an owned menu with at least two closed-set model rows. Refresh the owned menu after its bounded settle period. Open the nested effort menu by clicking the exact verified effort-row geometry because paid Claude's advertised `AXPress` action only focuses that row. Require at least three closed-set effort rows before selecting.
6. Prefer direct Accessibility actions. A frame-derived HID click is permitted only for the structurally verified composer popup or an exact row inside its verified owned menu. Revalidate the captured process/window immediately before delivery, constrain click points to current menu geometry, and restore the pointer afterward.
7. On Code, open the exact visible model popup, require at least three closed-set model rows in its owned menu, select one exact row, and verify the closed composer model. Open the exact effort popup and require one structurally related `AXSlider` exposing Increment and Decrement. Map only the exact `(numeric value, value description)` pairs Low `0`, Medium `1`, High `2`, Extra `3`, and Max `4`. Reacquire and verify the slider after each of at most four steps, close it, and verify the effort popup title.
8. Select only exact labels from closed source sets. Do not use list position, substring guessing, fixed screen coordinates, terminal commands, or settings-file edits. Verify Chat/Cowork through the combined composer title and Code through its closed composer controls; report failure even when an input appeared to work.
9. Keep terminal Claude Code integrations out of scope until a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content. Cursor Agent/Chat model switching is covered separately in [ADR-003](ADR-003-cursor-model-picker.md).

## Consequences

- The same shortcut can safely select different profiles depending on which supported app is frontmost.
- Claude UI or Accessibility changes disable the adapter instead of selecting by position.
- A signed Release build passed live switching in Claude Desktop 1.40609.0 on a paid account. Chat passed Sonnet 5 Medium to High plus an already-applied High run; Cowork passed High to Medium; Code passed Opus 5/Low to Sonnet 5/Medium and then Medium to High.
- Claude may append plan-usage copy to an effort row, such as `Max 2.5× or more usage` or `Max 3.5× or more usage`. ReasonDeck allowlists each observed full label and continues to reject unrecognized variants rather than matching a prefix.
- Current Code efforts are Low, Medium, High, Extra, and Max. Persisted Auto, None, or Ultracode assignments remain invalid for this live surface and are reported as unavailable instead of being coerced to a slider position.
- Claude choices can differ by plan or session. A missing exact item is reported as unavailable; ReasonDeck never substitutes a model or effort.

## Supersession condition

Prefer an official local Claude Code model-and-effort API if Anthropic exposes one that preserves active-session scoping and verifiable final state. Revisit terminal support separately when a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content.
