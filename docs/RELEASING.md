# Release procedure

Audience: maintainers publishing a GitHub Release and updating the custom Homebrew tap.

Owner: the repository maintainer.

Lifecycle: update this procedure whenever `scripts/release.sh`, `scripts/next-release.sh`, `.github/workflows/release.yml`, signing requirements, GitHub publication, or the Cask contract changes.

Releases are published automatically from `main`. `scripts/release.sh` itself only prepares and verifies artifacts; it never creates tags, pushes, uploads, or publishes. The sections after **Automated releases** describe the manual path, which is still required for live verification and for producing an artifact by hand.

## Automated releases

Pushing to `main` runs `.github/workflows/release.yml`. It publishes only when the pushed commits contain a releasable Conventional Commit subject:

| Commit type | Effect |
| --- | --- |
| `feat` | Minor version, listed under **Added** |
| `fix` | Patch version, listed under **Fixed** |
| `perf` | Patch version, listed under **Changed** |
| `refactor` | Listed under **Changed**, never releases on its own |
| `!` or a `BREAKING CHANGE:` trailer | Minor version while the major is `0`, marked **Breaking** |
| `docs`, `chore`, `ci`, `test`, `style`, `build` | No release |

The workflow runs `swift test`, derives the version with `scripts/next-release.sh`, writes `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, the `CHANGELOG.md` entry, and the README download links, commits and tags, then runs `scripts/release.sh` to produce the same signed, notarized, stapled DMG as the manual path. The commit and tag are pushed atomically only after that artifact verifies, so a failed build never leaves a public tag without a release. Its own release commit carries `[skip ci]` and cannot re-trigger the workflow.

A hand-written `## Unreleased` section in `CHANGELOG.md` becomes the release notes verbatim and replaces the generated bullets. Use it whenever a change needs Safety reasoning or wording that a commit subject cannot carry.

Preview what the next push would publish, changing nothing:

```sh
scripts/next-release.sh
```

Releases publish as prereleases. Set `PRERELEASE` to `"false"` in the workflow to change that.

### What automation cannot do

An automated release is signed, notarized, and unit-tested. It carries **no live Accessibility evidence**, and its notes say so explicitly. Section 4 remains mandatory, but now runs *after* publication instead of before it:

1. Download the published DMG and run every section 4 check against that exact artifact.
2. When the checks pass, edit the release notes to record the macOS version, target app versions, and architectures actually tested, then remove the unverified warning.
3. When they fail, follow **Rollback**.

Automation also never updates Homebrew, and never rewrites version claims in README prose. The live-certification sentences stay under human control so that no build can assert evidence it has not earned.

### Required secrets

The workflow fails closed when any of these repository secrets is missing, because an unsigned or un-notarized build would force users past Gatekeeper.

| Secret | Value |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERT_P12` | `base64 -i DeveloperID.p12` of the Developer ID Application certificate exported from Keychain Access with its private key |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | The password set during that `.p12` export |
| `APPLE_DEVELOPER_TEAM_ID` | The 10-character Apple team identifier |
| `APPLE_NOTARY_KEY_P8` | `base64 -i AuthKey_XXXXXXXXXX.p8` of an App Store Connect API key |
| `APPLE_NOTARY_KEY_ID` | That key's ID |
| `APPLE_NOTARY_ISSUER_ID` | The App Store Connect issuer UUID |
| `APPLE_SIGNING_IDENTITY` | Optional. The full `Developer ID Application: Name (TEAMID)` string, needed only when more than one identity resolves |

Create the notarization key in App Store Connect under Users and Access, Integrations, with Developer ID access. Apple allows a `.p8` to be downloaded once.

Storing a Developer ID certificate as a repository secret lets anyone who can run a workflow in this repository sign code as this team. Restrict who can push and who can edit workflows, and revoke the certificate in the Apple Developer portal if either is ever in doubt.

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

Automated releases perform steps 1 and 2 and publish in step 6. Follow this section by hand only when releasing without the workflow.

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
