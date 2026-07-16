#!/usr/bin/env bash
#
# Download an upstream LLVM pull-request diff and select a paired report path.
#
# Usage:
#   download-pr-diff.sh <pr-number> <workspace-root>

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"

die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  die "usage: $SCRIPT_NAME <pr-number> <workspace-root>"
fi

pr_number="$1"
workspace_root="$2"

[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] ||
  die "PR number must be a positive integer: $pr_number"
command -v gh >/dev/null 2>&1 || die "required command not found: gh"
[[ -d "$workspace_root" ]] ||
  die "workspace root is not a directory: $workspace_root"

workspace_root="$(cd "$workspace_root" && pwd -P)"
git -C "$workspace_root/src" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  die "workspace does not contain a Git checkout at: $workspace_root/src"

local_directory="$workspace_root/local"
temporary_root="/tmp/$(id -un)/codex"
mkdir -p "$local_directory" "$temporary_root" ||
  die "could not create output directories"
chmod 700 "$temporary_root" ||
  die "could not secure temporary directory: $temporary_root"

download_file="$(mktemp "$temporary_root/.diff-pr${pr_number}.XXXXXX")" ||
  die "could not create temporary download file"
cleanup() {
  rm -f "$download_file"
}
trap cleanup EXIT

pr_url="https://github.com/llvm/llvm-project/pull/$pr_number"
gh pr diff "$pr_url" --color never >"$download_file" ||
  die "failed to download diff for $pr_url"

suffix=1
while true; do
  diff_file="$temporary_root/diff-pr${pr_number}-${suffix}.diff"
  report_file="$local_directory/review-pr${pr_number}-${suffix}.md"
  if [[ ! -e "$diff_file" && ! -e "$report_file" ]]; then
    if ln "$download_file" "$diff_file" 2>/dev/null; then
      break
    fi
  fi
  ((suffix += 1))
done

printf '%s\n%s\n' "$diff_file" "$report_file"
