#!/bin/bash

# Derives the next release from Conventional Commits since the highest v* tag.
#
# Read-only by default so a maintainer can preview exactly what an automated
# push to main would publish. --apply writes the version into Config/Build.xcconfig
# and the notes into CHANGELOG.md; it never commits, tags, or publishes.
#
# Exit codes: 0 release derived, 3 nothing releasable, other values are errors.

set -euo pipefail

readonly CHANGELOG="CHANGELOG.md"
readonly BUILD_CONFIG="Config/Build.xcconfig"

fail() {
    printf 'next-release: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage:
  scripts/next-release.sh [--apply] [--notes-out <path>]

Prints shell-style key=value lines describing the next release:
  previous=v0.2.6
  version=0.2.7
  build=10
  bump=patch

Exits 3 without output when no commit since the last tag warrants a release.
USAGE
}

apply=false
notes_out=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            apply=true
            shift
            ;;
        --notes-out)
            [[ $# -ge 2 ]] || fail "--notes-out requires a value"
            notes_out="$2"
            shift 2
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "run from a Git repository"
[[ "$PWD" == "$repo_root" ]] || fail "run from the repository root: $repo_root"
[[ -f "$CHANGELOG" ]] || fail "missing $CHANGELOG"
[[ -f "$BUILD_CONFIG" ]] || fail "missing $BUILD_CONFIG"

config_value() {
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$BUILD_CONFIG" | awk 'NR == 1 { print; exit }'
}

current_version="$(config_value MARKETING_VERSION)"
current_build="$(config_value CURRENT_PROJECT_VERSION)"

[[ "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "MARKETING_VERSION must use MAJOR.MINOR.PATCH"
[[ "$current_build" =~ ^[0-9]+$ ]] || fail "CURRENT_PROJECT_VERSION must be an integer"

previous_tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | awk 'NR == 1 { print; exit }')"

if [[ -n "$previous_tag" ]]; then
    # Drift between the tag and the checked-in version means a release was
    # published or prepared by hand. Fail closed rather than guessing which
    # number is authoritative and publishing an immutable tag over the wrong one.
    [[ "${previous_tag#v}" == "$current_version" ]] \
        || fail "MARKETING_VERSION ($current_version) does not match the highest tag ($previous_tag)"
    range="$previous_tag..HEAD"
else
    range="HEAD"
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/reasondeck-next-release.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

added="$work_dir/added"
fixed="$work_dir/fixed"
changed="$work_dir/changed"
: >"$added"
: >"$fixed"
: >"$changed"

bump=""

# Conventional Commits precedence: a breaking change outranks feat, which
# outranks fix and perf. Anything else (docs, chore, ci, test, style, build)
# is deliberately not releasable on its own.
raise_bump() {
    case "$1" in
        major) bump="major" ;;
        minor) [[ "$bump" == "major" ]] || bump="minor" ;;
        patch) [[ -n "$bump" ]] || bump="patch" ;;
    esac
}

while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue

    subject="$(git log -1 --format=%s "$sha")"
    body="$(git log -1 --format=%b "$sha")"

    [[ "$subject" =~ ^([a-zA-Z]+)(\(([^\)]*)\))?(!)?:[[:space:]]+(.+)$ ]] || continue

    type="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    bang="${BASH_REMATCH[4]}"
    description="${BASH_REMATCH[5]}"

    breaking=false
    if [[ -n "$bang" ]] || printf '%s\n' "$body" | grep -Eq '^BREAKING[ -]CHANGE:'; then
        breaking=true
    fi

    entry="$(printf '%s' "$description" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"
    if $breaking; then
        entry="**Breaking:** $entry"
    fi

    case "$type" in
        feat)
            printf -- '- %s\n' "$entry" >>"$added"
            raise_bump minor
            ;;
        fix)
            printf -- '- %s\n' "$entry" >>"$fixed"
            raise_bump patch
            ;;
        perf|refactor)
            printf -- '- %s\n' "$entry" >>"$changed"
            [[ "$type" == "perf" ]] && raise_bump patch
            ;;
        *)
            # Non-releasable type. Still record a breaking marker so a breaking
            # chore or docs change cannot ship silently as an ordinary release.
            if $breaking; then
                printf -- '- %s\n' "$entry" >>"$changed"
            fi
            ;;
    esac

    if $breaking; then
        raise_bump major
    fi
done < <(git log --no-merges --format=%H "$range")

[[ -n "$bump" ]] || exit 3

major="${current_version%%.*}"
rest="${current_version#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"

# Semantic Versioning keeps a 0.x series unstable: a breaking change raises the
# minor component instead of declaring 1.0. CHANGELOG.md already commits to
# describing compatibility honestly during major version zero.
if [[ "$bump" == "major" && "$major" -eq 0 ]]; then
    bump="minor"
fi

case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
esac

next_version="$major.$minor.$patch"
next_build=$((current_build + 1))
release_date="$(date -u +%Y-%m-%d)"

# A hand-written Unreleased section wins over generated bullets. The changelog
# carries reasoning (notably Safety notes) that a commit subject cannot express,
# and docs/RELEASING.md already treats Unreleased as the staging area.
handwritten="$(awk '
    tolower($0) ~ /^## \[?unreleased\]?/ { flag = 1; next }
    /^## / { flag = 0 }
    flag { print }
' "$CHANGELOG" | sed -e '/./,$!d' | awk '{ lines[NR] = $0 } END { last = 0; for (i = 1; i <= NR; i++) if (lines[i] ~ /[^[:space:]]/) last = i; for (i = 1; i <= last; i++) print lines[i] }')"

notes_file="$work_dir/notes"
if [[ -n "$handwritten" ]]; then
    printf '%s\n' "$handwritten" >"$notes_file"
    notes_source="changelog-unreleased"
else
    : >"$notes_file"
    append_section() {
        [[ -s "$2" ]] || return 0
        [[ ! -s "$notes_file" ]] || printf '\n' >>"$notes_file"
        printf '### %s\n\n' "$1" >>"$notes_file"
        cat "$2" >>"$notes_file"
    }
    append_section Added "$added"
    append_section Fixed "$fixed"
    append_section Changed "$changed"
    notes_source="conventional-commits"
fi

[[ -s "$notes_file" ]] || fail "derived a $bump release with no release notes"

if [[ -n "$notes_out" ]]; then
    cat "$notes_file" >"$notes_out"
fi

printf 'previous=%s\n' "${previous_tag:-none}"
printf 'version=%s\n' "$next_version"
printf 'build=%s\n' "$next_build"
printf 'bump=%s\n' "$bump"
printf 'notes_source=%s\n' "$notes_source"

$apply || exit 0

tmp_config="$work_dir/Build.xcconfig"
sed \
    -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $next_version/" \
    -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $next_build/" \
    "$BUILD_CONFIG" >"$tmp_config"

grep -Fxq "MARKETING_VERSION = $next_version" "$tmp_config" || fail "failed to write MARKETING_VERSION"
grep -Fxq "CURRENT_PROJECT_VERSION = $next_build" "$tmp_config" || fail "failed to write CURRENT_PROJECT_VERSION"
cat "$tmp_config" >"$BUILD_CONFIG"

block="$work_dir/block"
{
    printf '## %s - %s\n\n' "$next_version" "$release_date"
    cat "$notes_file"
    printf '\n'
} >"$block"

tmp_changelog="$work_dir/CHANGELOG.md"
BLOCK="$(cat "$block")" awk '
    {
        if (!inserted && $0 ~ /^## /) {
            printf "%s\n\n", ENVIRON["BLOCK"]
            inserted = 1
            if (tolower($0) ~ /^## \[?unreleased\]?/) { skipping = 1; next }
        } else if (skipping && $0 ~ /^## /) {
            skipping = 0
        }
        if (skipping) next
        print
    }
    END { if (!inserted) printf "%s\n", ENVIRON["BLOCK"] }
' "$CHANGELOG" >"$tmp_changelog"

grep -Fq "## $next_version - $release_date" "$tmp_changelog" || fail "failed to write the changelog entry"
cat "$tmp_changelog" >"$CHANGELOG"

# The README download button must follow the published version, or the front
# page keeps offering an artifact that is no longer current. Only the download
# URL, the tag URL, and the button label move. Version claims in prose stay
# under human control: the live-certification sentences must never be rewritten
# to assert evidence that a new build has not earned.
#
# These patterns match any version in the link rather than the outgoing one, so
# a README that already drifted from MARKETING_VERSION is corrected instead of
# silently left pointing at a stale artifact.
if [[ -f README.md ]]; then
    semver='[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*'
    tmp_readme="$work_dir/README.md"
    sed \
        -e "s|/releases/download/v$semver/ReasonDeck-$semver\.dmg|/releases/download/v$next_version/ReasonDeck-$next_version.dmg|g" \
        -e "s|/releases/tag/v$semver|/releases/tag/v$next_version|g" \
        -e "s|\[Download ReasonDeck $semver for Mac\]|[Download ReasonDeck $next_version for Mac]|g" \
        README.md >"$tmp_readme"

    stale="$(grep -oE "releases/(download|tag)/v[0-9]+\.[0-9]+\.[0-9]+" "$tmp_readme" \
        | grep -Fv "v$next_version" || true)"
    [[ -z "$stale" ]] || fail "README still links a non-current release: $stale"

    cat "$tmp_readme" >README.md
fi
