#!/usr/bin/env bash
#
# Download PR review feedback added after the current branch was last pushed.
#
# Usage:
#   download-pr-reviews.sh [OUTPUT_FILE]
#   download-pr-reviews.sh --since 2026-07-15T12:00:00Z [OUTPUT_FILE]
#
# The optional --since override is useful when the local Git reflog does not
# contain the branch's last successful push.

set -euo pipefail

readonly UPSTREAM_REPOSITORY="llvm/llvm-project"
readonly SCRIPT_NAME="${0##*/}"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--since ISO-8601-TIMESTAMP] [OUTPUT_FILE]

Write Markdown containing review feedback added since the current branch was
last pushed to its GitHub fork. OUTPUT_FILE defaults to pr-reviews.md in the
directory from which the script is invoked.

--since overrides automatic push-time detection. Example:
  $SCRIPT_NAME --since 2026-07-15T12:00:00Z new-review-feedback.md
EOF
}

die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

status() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

markdown_blockquote() {
  # Prefix every line, including blank lines, so arbitrary GitHub Markdown is
  # preserved as readable quoted content in the generated Markdown report.
  sed 's/^/> /'
}

url_to_github_owner() {
  local url="$1"
  url="${url%.git}"

  case "$url" in
    git@github.com:*|ssh://git@github.com/*|https://github.com/*|http://github.com/*)
      ;;
    *)
      return 1
      ;;
  esac

  printf '%s\n' "$url" |
    sed -E \
      -e 's#^git@github\.com:##' \
      -e 's#^ssh://git@github\.com/##' \
      -e 's#^https?://github\.com/##' |
    awk -F/ 'NF >= 2 { print $1; exit }'
}

invocation_directory="$(pwd -P)"
since=""
output_argument=""

while (($#)); do
  case "$1" in
    --since)
      (($# >= 2)) || die "--since requires an ISO-8601 timestamp"
      since="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z "$output_argument" ]] || die "only one output file may be specified"
      output_argument="$1"
      shift
      ;;
  esac
done

if [[ -z "$output_argument" ]]; then
  output_argument="pr-reviews.md"
fi

case "$output_argument" in
  /*) output_file="$output_argument" ;;
  *) output_file="$invocation_directory/$output_argument" ;;
esac

require_command git
require_command gh
require_command jq

repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  die "run this from a Git working tree"
cd "$repository_root"

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || die "HEAD is detached; check out the PR branch first"
status "Current branch: $branch"

# Prefer the branch's push remote, then origin, then the first GitHub remote
# other than llvm/llvm-project. The PR lookup below is still authoritative.
fork_remote=""
upstream_ref="$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch")"
if [[ -n "$upstream_ref" && "$upstream_ref" == */* ]]; then
  candidate_remote="${upstream_ref%%/*}"
  candidate_url="$(git remote get-url --push "$candidate_remote" 2>/dev/null ||
    git remote get-url "$candidate_remote" 2>/dev/null || true)"
  if [[ -n "$candidate_url" ]] &&
     candidate_owner="$(url_to_github_owner "$candidate_url" 2>/dev/null)" &&
     [[ "$candidate_owner" != "llvm" ]]; then
    fork_remote="$candidate_remote"
  fi
fi

if [[ -z "$fork_remote" ]] && git remote get-url origin >/dev/null 2>&1; then
  candidate_url="$(git remote get-url --push origin 2>/dev/null ||
    git remote get-url origin)"
  if candidate_owner="$(url_to_github_owner "$candidate_url" 2>/dev/null)" &&
     [[ "$candidate_owner" != "llvm" ]]; then
    fork_remote="origin"
  fi
fi

if [[ -z "$fork_remote" ]]; then
  while IFS= read -r candidate_remote; do
    candidate_url="$(git remote get-url --push "$candidate_remote" 2>/dev/null ||
      git remote get-url "$candidate_remote")"
    if candidate_owner="$(url_to_github_owner "$candidate_url" 2>/dev/null)" &&
       [[ "$candidate_owner" != "llvm" ]]; then
      fork_remote="$candidate_remote"
      break
    fi
  done < <(git remote)
fi

[[ -n "$fork_remote" ]] ||
  die "could not identify a GitHub fork remote (expected a non-llvm GitHub remote)"

fork_url="$(git remote get-url --push "$fork_remote" 2>/dev/null ||
  git remote get-url "$fork_remote")"
fork_owner="$(url_to_github_owner "$fork_url")" ||
  die "remote '$fork_remote' is not a GitHub URL: $fork_url"
status "Using fork remote '$fork_remote' ($fork_owner)"

status "Finding the open PR against $UPSTREAM_REPOSITORY..."
pr_matches="$(gh api --paginate --slurp \
  --method GET \
  "repos/$UPSTREAM_REPOSITORY/pulls" \
  -f state=open \
  -f "head=$fork_owner:$branch" \
  -f per_page=100)"

# gh --slurp wraps each paginated response in an outer array.
pr_count="$(jq '[ .[] | .[] ] | length' <<<"$pr_matches")"
[[ "$pr_count" -eq 1 ]] ||
  die "expected exactly one open PR for head '$fork_owner:$branch' against $UPSTREAM_REPOSITORY; found $pr_count (using remote '$fork_remote': $fork_url)"
pr_number="$(jq -r '[ .[] | .[] ][0].number' <<<"$pr_matches")"

status "Found PR #$pr_number; loading PR metadata..."
pr_json="$(gh api "repos/$UPSTREAM_REPOSITORY/pulls/$pr_number")"
pr_url="$(jq -r '.html_url' <<<"$pr_json")"
pr_title="$(jq -r '.title' <<<"$pr_json")"
head_repository="$(jq -r '.head.repo.full_name // empty' <<<"$pr_json")"
[[ -n "$head_repository" ]] ||
  die "PR #$pr_number has no accessible head repository"

temporary_root="/tmp/$(id -un)/codex"
mkdir -p "$temporary_root" ||
  die "could not create temporary directory root: $temporary_root"
chmod 700 "$temporary_root" ||
  die "could not secure temporary directory root: $temporary_root"
temporary_directory="$(mktemp -d "$temporary_root/gh-address-pr-review.XXXXXX")" ||
  die "could not create temporary directory under: $temporary_root"
cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

cutoff_source="local Git push reflog"
if [[ -z "$since" ]]; then
  # `git push` updates the local remote-tracking reference and records that
  # update as "update by push" in its reflog. Its timestamp represents when
  # this checkout last successfully pushed this branch, unlike commit dates,
  # which may be much older.
  push_reference="refs/remotes/$fork_remote/$branch"
  status "Locating the local push history for $fork_remote/$branch..."
  push_reflog="$(git rev-parse --git-path "logs/$push_reference")"
  [[ -r "$push_reflog" ]] ||
    die "no local push history exists for $fork_remote/$branch. Re-run with --since <ISO-8601 timestamp> to choose the cutoff explicitly."
  status "Selecting the latest successful local push..."
  push_epoch="$(
    awk -F '\t' '
      $2 == "update by push" {
        # The part before the tab ends with
        # "<committer name> <email> <epoch> <UTC offset>".
        metadata = $1
        sub(/^.*> /, "", metadata)
        split(metadata, fields, " ")
        latest_epoch = fields[1]
      }
      END {
        if (latest_epoch != "") {
          print latest_epoch
        }
      }
    ' "$push_reflog"
  )"
  if [[ -n "$push_epoch" ]]; then
    since="$(jq -nr --argjson epoch "$push_epoch" '$epoch | todateiso8601')"
  fi

  if [[ -z "$since" ]]; then
    die "the local reflog has no recorded push for $fork_remote/$branch. Re-run with --since <ISO-8601 timestamp> to choose the cutoff explicitly."
  fi
  status "Using last local push as cutoff: $since"
else
  cutoff_source="--since argument"
  status "Using supplied cutoff: $since"
fi

# Verify before querying so a malformed override cannot silently create a
# report whose filter is unexpectedly empty.
jq -en --arg timestamp "$since" '$timestamp | fromdateiso8601' >/dev/null 2>&1 ||
  die "invalid ISO-8601 UTC timestamp: $since"

status "Downloading submitted reviews and inline comments since $since..."
reviews_json="$(gh api --paginate --slurp \
  "repos/$UPSTREAM_REPOSITORY/pulls/$pr_number/reviews?per_page=100")"
comments_json="$(gh api --paginate --slurp \
  "repos/$UPSTREAM_REPOSITORY/pulls/$pr_number/comments?per_page=100")"

# Flatten gh --slurp's pages and retain review submissions after the cutoff.
status "Filtering feedback and preparing the Markdown report..."
jq --arg since "$since" '
  [ .[] | .[] |
    select(.submitted_at != null and .submitted_at > $since)
  ]
' <<<"$reviews_json" >"$temporary_directory/reviews.json"

# An inline comment can be created while a review is pending, then submitted
# later. Keep it if either its own timestamp or its containing review's
# submission timestamp is newer than the cutoff.
jq --slurpfile reviews "$temporary_directory/reviews.json" --arg since "$since" '
  ($reviews[0] | map(.id) | map(tostring)) as $new_review_ids |
  [ .[] | .[] |
    select(
      .created_at > $since or
      (.pull_request_review_id != null and
       (.pull_request_review_id | tostring) as $review_id |
       $new_review_ids | index($review_id))
    )
  ]
' <<<"$comments_json" >"$temporary_directory/comments.json"

{
  printf '%s\n\n' "# Pull request review feedback"
  printf '%s\n' "- **Pull request:** [#$pr_number]($pr_url) — $pr_title"
  printf '%s\n' "- **Branch:** \`$branch\`"
  printf '%s\n' "- **Fork remote:** \`$fork_remote\` ($head_repository)"
  printf '%s\n' "- **Feedback since:** \`$since\` ($cutoff_source)"
  printf '%s\n\n' "- **Generated at:** \`$(date -u +'%Y-%m-%dT%H:%M:%SZ')\`"

  review_count="$(jq 'length' "$temporary_directory/reviews.json")"
  printf '%s\n\n' "## Submitted reviews ($review_count)"
  if [[ "$review_count" -eq 0 ]]; then
    printf '%s\n\n' "_No review submissions were made after the cutoff._"
  else
    while IFS= read -r review; do
      reviewer="$(jq -r '.user.login // "ghost"' <<<"$review")"
      state="$(jq -r '.state' <<<"$review")"
      submitted_at="$(jq -r '.submitted_at' <<<"$review")"
      review_url="$(jq -r '.html_url // empty' <<<"$review")"
      body="$(jq -r '.body // ""' <<<"$review")"
      if [[ -n "$review_url" ]]; then
        printf '%s\n\n' "### $state by @$reviewer at $submitted_at ([review]($review_url))"
      else
        printf '%s\n\n' "### $state by @$reviewer at $submitted_at"
      fi
      if [[ -n "$body" ]]; then
        printf '%s\n\n' "$body" | markdown_blockquote
        printf '\n'
      else
        printf '%s\n\n' "_No overall review message._"
      fi
    done < <(jq -c '.[]' "$temporary_directory/reviews.json")
  fi

  comment_count="$(jq 'length' "$temporary_directory/comments.json")"
  printf '%s\n\n' "## Inline review comments ($comment_count)"
  if [[ "$comment_count" -eq 0 ]]; then
    printf '%s\n' "_No inline review comments were added after the cutoff._"
  else
    while IFS= read -r comment; do
      commenter="$(jq -r '.user.login // "ghost"' <<<"$comment")"
      created_at="$(jq -r '.created_at' <<<"$comment")"
      comment_url="$(jq -r '.html_url' <<<"$comment")"
      path="$(jq -r '.path // "(unknown file)"' <<<"$comment")"
      line="$(jq -r '.line // .original_line // "unknown line"' <<<"$comment")"
      side="$(jq -r '.side // .original_side // ""' <<<"$comment")"
      body="$(jq -r '.body // ""' <<<"$comment")"
      diff_hunk="$(jq -r '.diff_hunk // ""' <<<"$comment")"

      printf '%s\n\n' "### \`$path:$line${side:+ ($side)}\` — @$commenter at $created_at ([comment]($comment_url))"
      printf '%s\n\n' "$body" | markdown_blockquote
      if [[ -n "$diff_hunk" ]]; then
        printf '%s\n' "<details><summary>Diff context</summary>"
        printf '\n```diff\n%s\n```\n\n' "$diff_hunk"
        printf '%s\n\n' "</details>"
      fi
    done < <(jq -c '.[]' "$temporary_directory/comments.json")
  fi
} >"$output_file"

status "Finished."
printf 'Wrote %s (%s submitted reviews, %s inline comments; cutoff %s).\n' \
  "$output_file" \
  "$(jq 'length' "$temporary_directory/reviews.json")" \
  "$(jq 'length' "$temporary_directory/comments.json")" \
  "$since"
