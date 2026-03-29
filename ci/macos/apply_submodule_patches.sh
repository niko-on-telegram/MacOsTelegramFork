#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() {
  printf '[patch] %s\n' "$*"
}

apply_patch_if_needed() {
  local repo_path="$1"
  local patch_path="$2"

  if git -C "$repo_path" apply --check "$patch_path" >/dev/null 2>&1; then
    log "Applying $(basename "$patch_path") in ${repo_path#$ROOT_DIR/}"
    git -C "$repo_path" apply "$patch_path"
    return
  fi

  if git -C "$repo_path" apply --reverse --check "$patch_path" >/dev/null 2>&1; then
    log "Patch already applied: $(basename "$patch_path")"
    return
  fi

  printf 'Patch does not apply cleanly: %s -> %s\n' "$patch_path" "$repo_path" >&2
  exit 1
}

apply_patch_if_needed \
  "$ROOT_DIR/submodules/tg_owt" \
  "$ROOT_DIR/ci/patches/tg_owt-absl-lifetime-bound.patch"
