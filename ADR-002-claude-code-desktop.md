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
5. On Chat/Cowork, open the exact combined popup and require an owned root menu containing the current closed-set model plus the exact `More models` row. Refresh the owned menu after its bounded settle period. Focus `More models` through its exact verified geometry and send native Right Arrow to perform that focused row's submenu transition. Require the owned nested menu to contain at least two closed-set alternative models, then select one exact model-row geometry. If the owned menus remain open because Chromium used that first click only to focus a non-default row, wait the same bounded 500-millisecond responder-settle period, then reacquire the exact nested menu and row before one activation click. Open the nested effort menu through its exact verified trigger geometry. Paid Claude's advertised `AXPress` actions can focus or close these rows without performing the intended nested-menu transition, so every geometry and key action retains owned-menu and final-state verification.
6. Prefer direct Accessibility actions. Chromium can report successful `AXPress` and `AXShowMenu` actions while leaving the exact Chat/Cowork composer popup closed; only after both actions fail observable menu verification may ReasonDeck reacquire that same exact popup and click its current frame. A frame-derived HID click is otherwise permitted only for an exact row inside the popup's verified owned menu. The `More models` trigger and its exact nested model row omit a standalone preparatory hover because that hover rebuilds the Chromium row before mouse-down; they still derive mouse-down from the current verified row frame. Mouse events carry empty flags instead of inheriting the triggering shortcut's modifiers, and do not carry ReasonDeck's synthetic-key sentinel because the event tap subscribes only to keyboard events and Chromium refuses marked or shortcut-modified mouse-down activation. Revalidate the captured process/window immediately before delivery, constrain click points to current geometry, and restore the pointer afterward.
7. On Code, open the exact visible model popup, require at least three closed-set model rows in its owned menu, select one exact row, and verify the closed composer model. Open the exact effort popup and require one structurally related `AXSlider` exposing Increment and Decrement. Map only the exact `(numeric value, value description)` pairs Low `0`, Medium `1`, High `2`, Extra `3`, and Max `4`. Reacquire and verify the slider after each of at most four steps, close it, and verify the effort popup title.
8. Select only exact labels from closed source sets. Do not use list position, substring guessing, fixed screen coordinates, terminal commands, or settings-file edits. Verify Chat/Cowork through the combined composer title and Code through its closed composer controls; report failure even when an input appeared to work.
9. Keep terminal Claude Code integrations out of scope until a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content. Cursor Agent/Chat model switching is covered separately in [ADR-003](ADR-003-cursor-model-picker.md).

## Consequences

- The same shortcut can safely select different profiles depending on which supported app is frontmost.
- Claude UI or Accessibility changes disable the adapter instead of selecting by position. The paid Chat/Cowork layout's exact `More models` transition is part of that closed contract.
- A signed Release build passed live switching in Claude Desktop 1.40609.0 on a paid account. Chat passed Sonnet 5 Medium to High plus an already-applied High run; Cowork passed High to Medium; Code passed Opus 5/Low to Sonnet 5/Medium and then Medium to High.
- Claude may append plan-usage copy to an effort row, such as `Max 2.5× or more usage` or `Max 3.5× or more usage`. ReasonDeck allowlists each observed full label and continues to reject unrecognized variants rather than matching a prefix.
- Current Code efforts are Low, Medium, High, Extra, and Max. Persisted Auto, None, or Ultracode assignments remain invalid for this live surface and are reported as unavailable instead of being coerced to a slider position.
- Claude choices can differ by plan or session. A missing exact item is reported as unavailable; ReasonDeck never substitutes a model or effort.

## Supersession condition

Prefer an official local Claude Code model-and-effort API if Anthropic exposes one that preserves active-session scoping and verifiable final state. Revisit terminal support separately when a host-specific integration can prove the focused Claude prompt without reading or modifying conversation content.
