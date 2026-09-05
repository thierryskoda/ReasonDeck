# Release procedure

Audience: maintainers publishing a GitHub Release and updating the custom Homebrew tap.

Owner: the repository maintainer.

Lifecycle: update this procedure whenever `scripts/release.sh`, signing requirements, GitHub publication, or the Cask contract changes.

The release command prepares and verifies artifacts. It never creates tags, pushes, uploads, or publishes.

## Prerequisites

- A clean `main` checkout at the reviewed release commit
- Apple Developer Program access
- The intended `Developer ID Application` certificate in the login keychain
- The matching team in ignored `Config/Local.xcconfig`
- A validated `notarytool` Keychain profile
- Current Xcode command-line tools
- Access to the `thierryskoda/reasondeck` repository
- Access to the `thierryskoda/homebrew-tap` repository after the Cask is introduced

Store notarization credentials interactively. Do not put an Apple ID password, app-specific password, API key, or certificate in the repository or command history.

```sh
xcrun notarytool store-credentials ReasonDeck
```

Follow Apple's current notarization authentication guidance when creating that Keychain profile.

## 1. Prepare the version

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Config/Build.xcconfig`.
2. Move the completed entries in `CHANGELOG.md` from **Unreleased** to the exact version and release date.
3. Confirm README requirements, exact tested versions for every claimed adapter, install steps, and known limitations. Do not add an adapter version to a release claim until it has its own signed live reliability evidence.
4. Commit the version preparation. Do not create or move a public tag yet.

Versions use `MAJOR.MINOR.PATCH`. During major version zero, every release note must describe compatibility honestly instead of implying a stable API contract.

## 2. Run source gates

```sh
swift test
xcodebuild \
  -project ReasonDeck.xcodeproj \
  -scheme ReasonDeck \
  -configuration Release \
  -derivedDataPath /private/tmp/ReasonDeck-ReleaseCheck \
  CODE_SIGNING_ALLOWED=NO \
  build
git status --short
```

The test suite and build must pass, and `git status --short` must be empty.

## 3. Build the release candidate

```sh
scripts/release.sh 0.1.0 --notary-profile ReasonDeck
```

If more than one Developer ID Application identity is installed, pass the intended full identity explicitly:

```sh
scripts/release.sh 0.1.0 \
  --notary-profile ReasonDeck \
  --identity "Developer ID Application: Name (TEAMID)"
```

The command must fail if the version, Git state, bundle identifier, team, identity, hardened runtime, entitlements, architectures, signatures, notarization, stapling, Gatekeeper assessment, or checksum is wrong.

Successful output is stored under `dist/v<version>/`:

- `ReasonDeck-<version>.dmg`
- `SHA256SUMS`
- `release-evidence.txt`
- Apple notarization reports
- Local diagnostic logs, which are not release assets

Large archive and packaging intermediates use a validated temporary directory and are removed when the command exits. If a failed run leaves `dist/v<version>/`, inspect its logs and remove that failed output directory before retrying the same version.

Only the DMG and `SHA256SUMS` are public release assets.

## 4. Perform live release checks

Use a clean macOS user account or another Mac.

1. Verify `SHA256SUMS` against the DMG.
2. Open the DMG and drag the app to Applications.
3. Launch without bypassing Gatekeeper.
4. Complete Accessibility and Input Monitoring from Settings.
5. Add, edit, and delete multiple shortcuts, including duplicate-conflict handling.
6. Relaunch and verify persistence.
7. Replace the previous same-bundle-ID build and verify saved shortcuts remain.
8. In an idle normal-layout ChatGPT conversation, verify menu selection and a recorded keyboard shortcut.
9. Bring another app frontmost and verify the same keys pass through.
10. For every enabled adapter, run its versioned signed live reliability matrix, including context-drift and permission-freshness checks. After any dispatcher or trusted-action change, run an alternating same-binary sequence: ChatGPT profile A → Cursor profile A → ChatGPT profile B → Cursor profile B, and verify each terminal state before continuing. CI and unit tests do not substitute for this gate.
11. Confirm no chat-content logs or unexpected network activity appear.

Record the macOS version, ChatGPT version, architectures actually tested, signing identity, artifact SHA-256, and any limitation in the GitHub release notes. A universal binary built on Apple silicon is not proof of runtime behavior on Intel hardware.

## 5. Review before publication

Run the repository's `workflow-review` and `shipping-and-launch` gates. Resolve every blocking or high-priority finding.

Before an external action, verify:

- GitHub account: `thierryskoda`
- Repository: `thierryskoda/reasondeck`
- Release commit and version
- Intended annotated tag `v<version>`
- DMG filename and SHA-256
- Release remains a prerelease for the first small cohort

Creating the repository, configuring `origin`, pushing, tagging, and publishing require an explicit approval checkpoint.

## 6. Publish the GitHub prerelease

After approval, create the immutable annotated tag from the reviewed commit and publish the prerelease with the DMG and `SHA256SUMS`. Release notes must include requirements, tested environments, installation steps, privacy boundaries, and known limitations.

Download both assets again from the public release. Re-run checksum, signature, notarization-ticket, Gatekeeper, DMG, and installation checks on the downloaded copies. Verify the release page from a logged-out browser.

Never replace an existing asset, checksum, or tag in place. Publish a patch version for any corrected build.

## 7. Update Homebrew

After the GitHub artifact passes public-download verification, update the custom Cask to the exact versioned DMG URL and SHA-256. Run Homebrew style, audit, install, launch, upgrade, uninstall, and opt-in zap checks before recommending the command in the README.

Do not submit the Cask to the central Homebrew repository for v0.1.

## Rollback

- Keep the immutable GitHub artifact and tag as evidence.
- Remove the broken version from the README and other recommended download paths.
- Remove or revert the Cask to the last known-good immutable version.
- Mark the affected release as a prerelease and explain the problem.
- Publish a new patch version after the full release gate passes.

If no known-good public version exists, offer no binary or Cask until a corrected release passes. Do not instruct users to bypass Gatekeeper.
