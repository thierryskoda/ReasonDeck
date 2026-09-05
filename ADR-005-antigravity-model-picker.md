# ADR-005: Antigravity model picker verification

- Status: Accepted
- Scope: Antigravity model-and-effort selection in the macOS helper

## Context

Antigravity exposes its model picker through macOS Accessibility when an idle composer is frontmost. Picker rows and the current-selection title combine the model and effort, for example `Claude Opus 4.6 (Thinking)` and `Select model, current: Claude Opus 4.6 (Thinking)`.

The original adapter matched only the model substring, ignored the requested effort, did not check the `AXPress` result, and returned the requested pair without observing the final state. A request for `Gemini 3.1 Pro High` could therefore press the visible `Gemini 3.1 Pro Low` row and falsely report success.

## Decision

Treat one Antigravity switch as a fail-closed, captured-window transaction:

1. Revalidate the exact frontmost process and focused-window identity before every scan or input event.
2. Open the picker with its documented Command-Slash shortcut through the trusted input boundary.
3. Accept a picker only when one exact closed current-selection title owns actionable `AXMenuItem` descendants for at least two distinct known models. Duplicate verified pickers are an error.
4. Resolve the requested row by an exact, source-owned full-title mapping. Antigravity 2.8.1's exact `Fast`-badged Medium Flash rows map to the canonical Medium selection; substring, prefix, model-only, and unknown trailing-copy matches remain invalid. A missing or duplicate exact row changes nothing.
5. Deliver `AXPress` once through the trusted action boundary and require the verified picker to close.
6. Reopen a fresh picker and parse its exact current-selection title back into the closed typed selection. Report success only when both observed values equal the request.
7. After exact read-back, accept an already-closed picker as the desired terminal UI state. Send Escape only while a fresh snapshot still proves the same Antigravity picker is open.
8. Read titles only from allowlisted control roles and retain only recognized closed labels. Never inspect editor or transcript text-node values, log unknown Accessibility text, or add network access.

## Alternatives considered

### Match the model name and trust the requested effort

Rejected. It cannot distinguish effort variants and turns an unverified request into false success.

### Trust a successful press action

Rejected. Accessibility action delivery does not prove that Antigravity accepted the selection or that the final effort is correct.

### Scan or log arbitrary visible text

Rejected. It expands the privacy surface and can mistake conversation or editor content for a control label.

## Consequences

- A successful switch visibly opens the picker a second time for independent final verification.
- A configured pair that Antigravity does not expose as one known exact row fails without selecting a similar row.
- UI or label drift disables this path until a signed live check establishes a new exact contract.

## Supersession condition

Revisit this decision if Antigravity provides a supported local model-selection API or exposes separate, exact model and effort controls. Preserve frontmost scoping, final-state verification, closed typed labels, and the privacy boundary in any replacement.
