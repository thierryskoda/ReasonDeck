# ADR-006: Runtime compatibility health

- Status: Accepted
- Scope: Visible version and picker-contract health for all supported app adapters

## Context

ReasonDeck automates private macOS Accessibility surfaces rather than a stable model-selection API. ChatGPT, Claude Desktop Chat/Cowork/Code, Cursor, and Antigravity expose different controls, and those controls can change between app versions. A passing build or unit suite cannot prove that a newly installed app version still exposes the signed-live picker contract. Hiding that uncertainty makes a safe fail-closed result look like a broken shortcut.

Version allowlisting alone would be equally brittle: harmless patch releases would become unusable even when their exact Accessibility structure still passes every adapter preflight and final-state check.

## Decision

1. Show one compact compatibility row per supported app in Settings, including its locally detected version and whether it is running.
2. Label an exact version **Verified** only when its source-owned certification set is backed by recorded signed-live switching evidence. Never infer certification from semantic version proximity.
3. Label an uncertified version **Working, unverified** only after a successful or already-applied profile transaction in that exact running process. A non-contract partial result, such as an unavailable entitled effort after a verified model change, also proves the adapter is working without certifying the version.
4. Label an app **Needs update** only after a typed picker-contract, action, timeout, or final-verification failure. Do not degrade compatibility health for permissions, installation, focus, target drift, invalid configuration, a missing supported composer, account entitlement, a missing exact choice, or Cursor unread-navigation state.
5. Bind every runtime observation to the exact app version and process identifier. Discard it when the app quits, relaunches, or changes version. Keep observations in memory only; do not add telemetry, network access, UI dumps, or persistent diagnostics.
6. Treat **Unknown** as advisory, not a version gate. Existing adapters remain authoritative: they must prove the correct frontmost window, supported composer, owned picker, exact label, actionable control, and final state before reporting success. They stop instead of guessing when that proof fails.
7. Update health by observing existing typed switch results. Do not add picker probes, clicks, keystrokes, or Accessibility reads solely for compatibility reporting.

## Consequences

- Users can distinguish a known live-tested version, a locally working newer version, and a failed picker contract without ReasonDeck pretending every app update is safe.
- A new version can continue working immediately when its verified structure is unchanged, but it is not publicly certified until signed live evidence is recorded in source.
- **Needs update** is a strong compatibility signal, not a diagnosis by itself. Retrying in the documented idle layout separates a transient surface issue from persistent UI drift.
- The feature does not make private UI stable. It makes uncertainty and fail-closed behavior visible while preserving the exact per-app adapter contracts.

## Supersession condition

Replace runtime UI-contract health with supported provider APIs when those APIs can prove active-session scope and final model-and-effort state without collecting conversation content. Preserve explicit version evidence and honest uncertainty in any replacement.
