#!/bin/bash

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

readonly PROJECT="ReasonDeck.xcodeproj"
readonly SCHEME="ReasonDeck"
readonly APP_BUNDLE_ID="com.thierryai.ReasonDeck"
readonly EXPORTED_APP_NAME="ReasonDeck.app"
readonly DISTRIBUTED_APP_NAME="ReasonDeck.app"

fail() {
    printf 'release: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage:
  scripts/release.sh <version> --notary-profile <keychain-profile>
      [--identity "Developer ID Application: Name (TEAMID)"]
      [--preflight-only]

Creates a Developer ID-signed, notarized, stapled universal DMG under
dist/v<version>/. The command never creates tags, pushes, or publishes.

Store notarization credentials before running:
  xcrun notarytool store-credentials <keychain-profile>
USAGE
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

version="${1:-}"
if [[ -z "$version" || "$version" == -* ]]; then
    usage
    exit 2
fi
shift

notary_profile=""
requested_identity=""
preflight_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notary-profile)
            [[ $# -ge 2 ]] || fail "--notary-profile requires a value"
            notary_profile="$2"
            shift 2
            ;;
        --identity)
            [[ $# -ge 2 ]] || fail "--identity requires a value"
            requested_identity="$2"
            shift 2
            ;;
        --preflight-only)
            preflight_only=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must use MAJOR.MINOR.PATCH"
[[ -n "$notary_profile" ]] || fail "--notary-profile is required"

for tool in awk basename cat codesign ditto git grep hdiutil lipo ln mkdir mktemp plutil rm security sed shasum spctl tail xcodebuild xcrun; do
    require_command "$tool"
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "run from a Git repository"
[[ "$PWD" == "$repo_root" ]] || fail "run from the repository root: $repo_root"

git_status="$(git status --porcelain --untracked-files=normal)"
[[ -z "$git_status" ]] || fail "working tree must be clean before packaging"

expected_tag="v$version"
head_commit="$(git rev-parse HEAD)"
tags_at_head="$(git tag --points-at HEAD --list 'v*')"
unexpected_tags="$(printf '%s\n' "$tags_at_head" | grep -Fvx "$expected_tag" || true)"
[[ -z "$unexpected_tags" ]] || fail "HEAD has a different version tag: $unexpected_tags"

tag_state="not-created"
if git rev-parse --verify --quiet "refs/tags/$expected_tag" >/dev/null; then
    tag_commit="$(git rev-list -n 1 "$expected_tag")"
    [[ "$tag_commit" == "$head_commit" ]] || fail "$expected_tag does not point to HEAD"
    tag_state="points-to-head"
fi

build_settings="$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -showBuildSettings 2>/dev/null)"

build_setting() {
    printf '%s\n' "$build_settings" | sed -n "s/^[[:space:]]*$1 = //p" | awk 'NR == 1 { print; exit }'
}

effective_version="$(build_setting MARKETING_VERSION)"
effective_build="$(build_setting CURRENT_PROJECT_VERSION)"
effective_bundle_id="$(build_setting PRODUCT_BUNDLE_IDENTIFIER)"
effective_team="$(build_setting DEVELOPMENT_TEAM)"
effective_archs="$(build_setting ARCHS)"
effective_hardened_runtime="$(build_setting ENABLE_HARDENED_RUNTIME)"
effective_base_entitlements="$(build_setting CODE_SIGN_INJECT_BASE_ENTITLEMENTS)"

[[ "$effective_version" == "$version" ]] || fail "requested version $version does not match Xcode version $effective_version"
[[ "$effective_bundle_id" == "$APP_BUNDLE_ID" ]] || fail "unexpected bundle identifier: $effective_bundle_id"
[[ "$effective_hardened_runtime" == "YES" ]] || fail "Release must enable the hardened runtime"
[[ "$effective_base_entitlements" == "NO" ]] || fail "Release must disable injected base entitlements"
[[ " $effective_archs " == *" arm64 "* && " $effective_archs " == *" x86_64 "* ]] || fail "Release ARCHS must include arm64 and x86_64"

available_identities="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p')"

if [[ -n "$requested_identity" ]]; then
    printf '%s\n' "$available_identities" | grep -Fxq "$requested_identity" \
        || fail "the requested Developer ID Application identity is not installed"
    release_identity="$requested_identity"
else
    identity_count="$(printf '%s\n' "$available_identities" | awk 'NF { count++ } END { print count + 0 }')"
    [[ "$identity_count" -gt 0 ]] || fail "no Developer ID Application identity is installed"
    [[ "$identity_count" -eq 1 ]] || fail "multiple Developer ID Application identities found; pass --identity explicitly"
    release_identity="$available_identities"
fi

team_id="$(printf '%s\n' "$release_identity" | sed -E 's/^.*\(([A-Z0-9]{10})\)$/\1/')"
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || fail "could not derive the team ID from the Developer ID identity"
[[ -n "$effective_team" ]] || fail "DEVELOPMENT_TEAM is missing from local Xcode configuration"
[[ "$effective_team" == "$team_id" ]] || fail "local DEVELOPMENT_TEAM does not match the Developer ID identity"

printf 'Preflight passed for %s (%s).\n' "$expected_tag" "$head_commit"
printf 'Identity: %s\n' "$release_identity"
printf 'Architectures: %s\n' "$effective_archs"

if $preflight_only; then
    exit 0
fi

output_dir="$repo_root/dist/$expected_tag"
[[ ! -e "$output_dir" ]] || fail "output already exists: $output_dir"

logs_dir="$output_dir/logs"
work_dir="$(mktemp -d "/private/tmp/ReasonDeck-release-$version.XXXXXX")"
archive_path="$work_dir/ReasonDeck.xcarchive"
export_path="$work_dir/export"
export_options="$work_dir/ExportOptions.plist"
exported_app="$export_path/$EXPORTED_APP_NAME"
staging_dir="$work_dir/dmg-root"
distributed_app="$staging_dir/$DISTRIBUTED_APP_NAME"
app_zip="$work_dir/ReasonDeck-$version.zip"
dmg_path="$output_dir/ReasonDeck-$version.dmg"
checksum_path="$output_dir/SHA256SUMS"
evidence_path="$output_dir/release-evidence.txt"
app_notary_report="$output_dir/notarization-app.json"
dmg_notary_report="$output_dir/notarization-dmg.json"

mounted=false
mount_dir=""
cleanup() {
    if $mounted && [[ -n "$mount_dir" ]]; then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    if [[ "$work_dir" == /private/tmp/ReasonDeck-release-* ]]; then
        rm -rf "$work_dir"
    fi
}
trap cleanup EXIT

mkdir -p "$logs_dir" "$export_path" "$staging_dir"

plutil -create xml1 "$export_options"
plutil -insert destination -string export "$export_options"
plutil -insert method -string developer-id "$export_options"
plutil -insert signingStyle -string manual "$export_options"
plutil -insert signingCertificate -string "$release_identity" "$export_options"
plutil -insert teamID -string "$team_id" "$export_options"
plutil -insert stripSwiftSymbols -bool NO "$export_options"

printf 'Archiving Developer ID Release…\n'
if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    -hideShellScriptEnvironment \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$release_identity" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    archive >"$logs_dir/archive.log" 2>&1; then
    tail -80 "$logs_dir/archive.log" >&2
    fail "Xcode archive failed; see $logs_dir/archive.log"
fi

printf 'Exporting Developer ID app…\n'
if ! xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -hideShellScriptEnvironment >"$logs_dir/export.log" 2>&1; then
    tail -80 "$logs_dir/export.log" >&2
    fail "Xcode export failed; see $logs_dir/export.log"
fi

[[ -d "$exported_app" ]] || fail "exported app not found: $exported_app"

actual_version="$(plutil -extract CFBundleShortVersionString raw "$exported_app/Contents/Info.plist")"
actual_build="$(plutil -extract CFBundleVersion raw "$exported_app/Contents/Info.plist")"
actual_bundle_id="$(plutil -extract CFBundleIdentifier raw "$exported_app/Contents/Info.plist")"
actual_archs="$(lipo -archs "$exported_app/Contents/MacOS/ReasonDeck")"

[[ "$actual_version" == "$version" ]] || fail "exported app version mismatch: $actual_version"
[[ "$actual_build" == "$effective_build" ]] || fail "exported app build mismatch: $actual_build"
[[ "$actual_bundle_id" == "$APP_BUNDLE_ID" ]] || fail "exported app bundle identifier mismatch: $actual_bundle_id"
[[ " $actual_archs " == *" arm64 "* && " $actual_archs " == *" x86_64 "* ]] || fail "exported app is not universal: $actual_archs"

codesign --verify --deep --strict --verbose=4 "$exported_app" >"$logs_dir/codesign-verify-app.log" 2>&1 \
    || fail "exported app signature verification failed"
codesign -d --verbose=4 "$exported_app" 2>"$logs_dir/codesign-app.txt"
codesign -d --entitlements :- "$exported_app" >"$logs_dir/entitlements.plist" 2>"$logs_dir/entitlements.log"

grep -Fq "Authority=$release_identity" "$logs_dir/codesign-app.txt" || fail "exported app uses the wrong signing authority"
grep -Fq "TeamIdentifier=$team_id" "$logs_dir/codesign-app.txt" || fail "exported app uses the wrong team identifier"
grep -Eq '^flags=.*runtime' "$logs_dir/codesign-app.txt" || fail "exported app is missing hardened runtime flags"
grep -Eq '^Timestamp=' "$logs_dir/codesign-app.txt" || fail "exported app is missing a secure timestamp"

get_task_allow="$(plutil -extract com.apple.security.get-task-allow raw "$logs_dir/entitlements.plist" 2>/dev/null || true)"
[[ "$get_task_allow" != "true" ]] || fail "exported app contains get-task-allow"

submit_notarization() {
    local artifact="$1"
    local report="$2"
    local log_name="$3"

    if ! xcrun notarytool submit "$artifact" \
        --keychain-profile "$notary_profile" \
        --wait \
        --output-format json >"$report"; then
        fail "notarization submission failed for $artifact"
    fi

    local status
    local submission_id
    status="$(plutil -extract status raw "$report" 2>/dev/null || true)"
    submission_id="$(plutil -extract id raw "$report" 2>/dev/null || true)"

    if [[ "$status" != "Accepted" ]]; then
        if [[ -n "$submission_id" ]]; then
            xcrun notarytool log "$submission_id" \
                --keychain-profile "$notary_profile" \
                "$logs_dir/$log_name" >/dev/null 2>&1 || true
        fi
        fail "notarization was not accepted for $artifact (status: ${status:-unknown})"
    fi

    printf '%s' "$submission_id"
}

printf 'Notarizing app…\n'
ditto -c -k --sequesterRsrc --keepParent "$exported_app" "$app_zip"
app_submission_id="$(submit_notarization "$app_zip" "$app_notary_report" notarization-app-log.json)"
xcrun stapler staple -v "$exported_app" >"$logs_dir/staple-app.log" 2>&1
xcrun stapler validate -v "$exported_app" >"$logs_dir/staple-validate-app.log" 2>&1
spctl --assess --type execute --verbose=4 "$exported_app" >"$logs_dir/gatekeeper-app.log" 2>&1

ditto "$exported_app" "$distributed_app"
ln -s /Applications "$staging_dir/Applications"

printf 'Creating signed disk image…\n'
hdiutil create \
    -volname "ReasonDeck" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path" >"$logs_dir/hdiutil-create.log" 2>&1
codesign --force --timestamp --sign "$release_identity" "$dmg_path" >"$logs_dir/codesign-dmg.log" 2>&1
codesign --verify --verbose=4 "$dmg_path" >"$logs_dir/codesign-verify-dmg.log" 2>&1
hdiutil verify "$dmg_path" >"$logs_dir/hdiutil-verify.log" 2>&1

printf 'Notarizing disk image…\n'
dmg_submission_id="$(submit_notarization "$dmg_path" "$dmg_notary_report" notarization-dmg-log.json)"
xcrun stapler staple -v "$dmg_path" >"$logs_dir/staple-dmg.log" 2>&1
xcrun stapler validate -v "$dmg_path" >"$logs_dir/staple-validate-dmg.log" 2>&1
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path" >"$logs_dir/gatekeeper-dmg.log" 2>&1

mount_dir="$work_dir/mounted"
mkdir -p "$mount_dir"

hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$dmg_path" >"$logs_dir/hdiutil-attach.log" 2>&1
mounted=true
mounted_app="$mount_dir/$DISTRIBUTED_APP_NAME"
[[ -d "$mounted_app" ]] || fail "app missing from final disk image"
codesign --verify --deep --strict --verbose=4 "$mounted_app" >"$logs_dir/codesign-verify-mounted-app.log" 2>&1
xcrun stapler validate -v "$mounted_app" >"$logs_dir/staple-validate-mounted-app.log" 2>&1
spctl --assess --type execute --verbose=4 "$mounted_app" >"$logs_dir/gatekeeper-mounted-app.log" 2>&1
hdiutil detach "$mount_dir" >"$logs_dir/hdiutil-detach.log" 2>&1
mounted=false

digest="$(shasum -a 256 "$dmg_path" | awk '{ print $1 }')"
printf '%s  %s\n' "$digest" "$(basename "$dmg_path")" >"$checksum_path"
(cd "$output_dir" && shasum -a 256 -c SHA256SUMS) >"$logs_dir/checksum-verify.log" 2>&1

cat >"$evidence_path" <<EVIDENCE
Version: $version
Build: $actual_build
Expected tag: $expected_tag
Tag state: $tag_state
Git commit: $head_commit
Bundle identifier: $actual_bundle_id
Signing identity: $release_identity
Team identifier: $team_id
Architectures: $actual_archs
App notarization submission: $app_submission_id
DMG notarization submission: $dmg_submission_id
SHA-256: $digest
EVIDENCE

printf '\nRelease artifact verified. No files were published.\n'
printf 'DMG: %s\n' "$dmg_path"
printf 'Checksums: %s\n' "$checksum_path"
printf 'Evidence: %s\n' "$evidence_path"
