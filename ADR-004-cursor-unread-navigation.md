# ADR-004: Cursor finished-session navigation

## Status

Accepted

## Context

Cursor’s Agents window tracks finished agent sessions waiting for a reply (blue-dot rows; internally related to done agents with unread/attention state) but ships no command such as `glass.nextUnreadDoneAgent`. Sequential navigation (`glass.nextAgentDirect`, `⌃Tab`) is MRU or list order, not finished-waiting-filtered.

ReasonDeck already automates Cursor through Accessibility for model switching. Users want a keyboard shortcut that jumps to the next finished coding session that is waiting for a reply, without leaving the Agents window.

## Decision

Add a separate Cursor-only navigation action, **Next finished session**, bound through the existing ReasonDeck shortcut system. It is not modeled as a fake model/effort profile. Persisted raw value remains `nextUnreadSession` for configuration compatibility.

Implementation:

1. **Configuration** — `ShortcutEntry` may set `cursorNavigation: .nextUnreadSession` instead of `cursor: CursorSelection`. Settings expose this on a dedicated **Finished** tab, separate from model shortcuts. Cursor remains an enabled target for that entry.
2. **Discovery** — Prefer a Cursor window titled Agents; locate agent sidebar rows (left column, activatable, titled).
3. **Finished-waiting signal** — Prefer Accessibility title tokens `Completed`, `Completed, unread …`, or `Needs attention`. Fall back to a tiny unnamed leading (or trailing) child when present. Cursor often does not expose the blue dot itself to Accessibility.
4. **Eligibility** — Only activatable left-sidebar `AXButton` rows whose titles look like agent sessions. Skip chrome (`New Chat`, `Search`, …). Skip in-progress titles.
5. **Selection** — Prefer the open Agents chat title (`Chat title. …`) when AX `selected` is missing (common in Electron). Walk rows top-to-bottom; choose the next eligible finished-waiting row after the current session, wrapping once to a different eligible row. If the only eligible row is already open, fail closed rather than re-activating the same row.
6. **Verification** — Activate the row, then confirm the open chat title matches, the finished-waiting token clears, or the row reports selected. Fail closed on mismatch.
7. **Failures** — Distinct errors for missing sidebar (`cursorUnreadNavigationUnavailable`), no eligible finished session (`cursorNoUnreadSessions`), and markers not exposed (`cursorUnreadStateNotObservable`).

We do not read Cursor’s on-disk composer state, scrape SQLite, or fall back to sequential next-chat navigation.

## Consequences

- Depends on Cursor exposing finished-waiting state through Accessibility titles (or dots); Electron may hide markers in some builds or layouts, and nested rows may be virtualized out of the tree.
- A first-party `glass.nextUnreadDoneAgent` / next-finished-agent command would be preferable; this adapter should be removed or demoted if Cursor ships it.
- Live verification in a signed Release build with real finished-waiting sessions is required when changing discovery or activation logic.

## Alternatives considered

- **Keybinding only** — No Cursor command exists; rejected.
- **MRU switcher (`glass.openRecentAgents`)** — Not finished-waiting-filtered; rejected.
- **Composer chat tabs (`composer.nextChatTab`)** — Different surface; rejected.
