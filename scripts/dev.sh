#!/bin/bash

set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"

fail() {
    printf 'dev: %s\n' "$*" >&2
    exit 1
}

[[ $# == 0 ]] || fail "Usage: scripts/dev.sh"
[[ -f Config/Local.xcconfig ]] || fail "Configure Config/Local.xcconfig with your stable signing team and identity first; see README.md."

build_dir="$repo_dir/build/dev"
build_log="$repo_dir/build/dev-build.log"
built_app="$build_dir/Build/Products/Release/ReasonDeck.app"
installed_app="/Applications/ReasonDeck.app"
installed_executable="$installed_app/Contents/MacOS/ReasonDeck"
mkdir -p "$repo_dir/build"

printf 'Running tests…\n'
swift test --scratch-path "$repo_dir/build/dev-tests"

printf 'Building signed Release…\n'
if ! xcodebuild -project ReasonDeck.xcodeproj -scheme ReasonDeck \
    -configuration Release -derivedDataPath "$build_dir" build > "$build_log" 2>&1; then
    tail -n 40 "$build_log" >&2
    fail "Build failed; the installed app was left running. Full log: $build_log"
fi

# TCC matches the designated requirement, not the binary hash or app filename.
# Reject a signing change before replacing a copy whose permissions already work.
codesign --verify --deep --strict \
    -R='anchor apple generic and identifier "com.thierryai.ReasonDeck"' "$built_app"
if [[ -e "$installed_app" ]]; then
    installed_requirement="$(codesign -d -r- "$installed_app" 2>&1 | sed -n 's/^designated => //p')"
    built_requirement="$(codesign -d -r- "$built_app" 2>&1 | sed -n 's/^designated => //p')"
    [[ -n "$installed_requirement" && "$installed_requirement" == "$built_requirement" ]] \
        || fail "Signing identity differs from the installed copy. Match Config/Local.xcconfig to its identity; no app or permissions were changed."
fi

# Copy into a fresh bundle: ditto merges directories and would retain deleted files.
# Stage on the destination filesystem so replacing the complete bundle uses renames.
staging_dir="$(mktemp -d /Applications/.ReasonDeck-update.XXXXXX)"
staged_app="$staging_dir/ReasonDeck.app"
previous_app="$staging_dir/previous.app"
update_complete=false
cleanup() {
    result=$?
    trap - EXIT
    if [[ "$update_complete" == false && -e "$previous_app" ]]; then
        rm -rf "$installed_app"
        if ! mv "$previous_app" "$installed_app"; then
            printf 'dev: Restore failed; previous app retained at %s\n' "$previous_app" >&2
            exit 1
        fi
        [[ -z "${running_pids:-}" ]] || open -n "$installed_app"
    fi
    rm -rf "$staging_dir"
    exit "$result"
}
trap cleanup EXIT
ditto "$built_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"

# Refuse another checkout's process instead of updating one copy while using another.
running_pids="$(pgrep -u "$UID" -x ReasonDeck || true)"
for pid in $running_pids; do
    executable="$(ps -p "$pid" -o comm=)"
    [[ "$executable" == "$installed_executable" ]] \
        || fail "Another ReasonDeck copy is running at $executable. Quit it before updating."
done

for pid in $running_pids; do
    kill -TERM "$pid"
    for ((attempt = 0; attempt < 50; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    ! kill -0 "$pid" 2>/dev/null || fail "ReasonDeck did not quit; the installed copy was not replaced."
done

printf 'Updating /Applications/ReasonDeck.app…\n'
if [[ -e "$installed_app" ]]; then
    mv "$installed_app" "$previous_app"
fi
mv "$staged_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
open -n "$installed_app"

for ((attempt = 0; attempt < 50; attempt++)); do
    relaunched_pids="$(pgrep -u "$UID" -x ReasonDeck || true)"
    for pid in $relaunched_pids; do
        if [[ "$(ps -p "$pid" -o comm=)" == "$installed_executable" ]]; then
            update_complete=true
            printf 'Updated and relaunched ReasonDeck (PID %s). Signing identity preserved; saved shortcuts were kept.\n' "$pid"
            exit 0
        fi
    done
    sleep 0.1
done

fail "The update installed, but launch could not be verified. Build log: $build_log"
