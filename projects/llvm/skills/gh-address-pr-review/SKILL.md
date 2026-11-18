---
name: gh-address-pr-review
description: Download, assess, and address GitHub pull-request review feedback for the current branch while keeping all responses local. Use when asked to handle, resolve, assess, address, or respond to PR review comments on the current branch, especially for LLVM pull requests from a personal fork. Produces unstaged code changes and a Markdown report containing the original feedback, assessment, action taken, and proposed response; never posts comments or pushes changes.
---

# Address GitHub PR Review

Address new review feedback on the current branch. Make justified code changes, consult the user about ambiguous feedback, and leave a local response report. Do not post to GitHub, stage, commit, or push.

## Command discipline

Keep shell invocations short so the configured permissions can recognize
routine commands and one approval can cover the bundled downloader.

- Run one command per tool call.
- Do not combine commands with `&&`, `;`, pipes, redirections, command
  substitutions, shell variables, loops, or inline scripts.
- Prefer direct commands such as `pwd -P`, `git status --short`, `date +%F`,
  `mkdir -p <directory>`, `chmod 700 <directory>`, and `mktemp <template>`.
- Use the agent's file-reading and file-editing tools instead of shell commands when
  inspecting or writing files.
- Invoke `scripts/download-pr-reviews.sh` directly as its own command. If it
  needs approval, request a reusable approval for that script prefix; do not
  wrap it in a larger shell command.
- When a later command needs a value such as a path, copy the literal value
  from the previous command's output into the next command instead of storing
  it in a shell variable.

## Workflow

1. Confirm the working tree and current branch.
   - Capture the initial session root from the session environment before changing any tool working directory. Do not derive it from `git rev-parse`, because the session root and repository root may differ:

     ```bash
     pwd -P
     ```

   - Remember the returned path as `session_root`; do not assign it in the shell.
   - Run `git status --short`.
   - Preserve all pre-existing user changes.
   - Note which files were already modified so they are not mistaken for review-driven changes.

2. Create a temporary file and download the review.
   - Resolve this skill's directory from the loaded `SKILL.md`.
   - Ensure the agent temporary directory specified by `AGENTS.md` exists. Run
     each command separately, replacing `<username>` with the known literal
     username:

     ```bash
     id -un
     mkdir -p /tmp/<username>/agent
     chmod 700 /tmp/<username>/agent
     mktemp /tmp/<username>/agent/gh-address-pr-review.XXXXXX
     ```

   - Remember the literal path printed by `mktemp` as `review_tmp_file`; do not
     assign it in the shell.
   - Run the downloader as one standalone command with literal paths:

     ```bash
     <skill-directory>/scripts/download-pr-reviews.sh <review_tmp_file>
     ```

   - If approval is required, request a reusable prefix approval for
     `<skill-directory>/scripts/download-pr-reviews.sh`.
   - If automatic cutoff detection fails, explain why and ask the user for an ISO-8601 cutoff to pass with `--since`. Do not invent a cutoff.
   - Read the complete downloaded file before editing code.

3. Inspect relevant code and assess every review item.
   - Treat overall review messages as items when they contain actionable requests.
   - Treat every inline comment as a separate item.
   - Examine the current code, surrounding context, tests, and project conventions before deciding.
   - Classify each item as:
     - `accepted`: the feedback applies and has a clear implementation.
     - `not-applicable`: the current code already addresses it, the premise is incorrect, or the requested change should not be made.
     - `needs-user-input`: intent or tradeoffs remain materially ambiguous after inspecting the repository.
   - Do not accept comments mechanically. Reviewers can be mistaken or can be commenting on outdated code.

4. Resolve ambiguous items with the user.
   - Explain the ambiguity and concrete alternatives.
   - Ask the smallest question needed to proceed.
   - Continue assessing independent items before waiting when possible.
   - Record the user's decision in the final report.

5. Implement accepted feedback.
   - Make focused changes that address the reviewer's underlying concern.
   - Add or update tests when appropriate.
   - Do not modify unrelated code.
   - Do not stage, commit, push, submit a review, resolve a conversation, or post any response.

6. Verify the result.
   - Run focused formatting, builds, and tests appropriate to the changed code.
   - Report failures honestly; do not hide or work around unrelated failures.
   - Re-read the diff and check that each accepted item is fully addressed.
   - Confirm all resulting code changes remain unstaged with `git status --short`.

7. Write the local response report.
   - Write the report in `session_root`, not the Git repository root, unless the user specifies another directory.
   - Use `pr-review-responses-YYYY-MM-DD.md`, based on the local calendar date.
   - Run `date +%F` as a standalone command. Use the returned literal date in
     the filename.
   - Do not overwrite an existing report. Check candidate paths with file tools
     rather than a shell loop. If the date-based name exists, try `-2`, `-3`,
     and so on until an unused path is found.

   - Preserve the PR metadata and original review text from the downloaded report.
   - For each actionable review item, append:

     ```markdown
     #### Assessment

     **Disposition:** accepted | not-applicable | needs-user-input
     **Rationale:** Brief technical assessment.
     **Action:** Files or tests changed, or "No code change."

     #### Proposed response

     Concise response suitable for the reviewer.
     ```

   - For accepted items, state what changed and mention relevant validation.
   - For not-applicable items, politely explain the technical reason.
   - For user-decided items, summarize the decision without exposing unnecessary internal deliberation.
   - Keep original comment links and code locations intact.
   - Ensure the report itself is not staged.
   - Remove only the literal `review_tmp_file` path after the final report has
     safely incorporated the original feedback. Run that removal as one
     standalone command. Never remove `/tmp/<username>/agent` because other
     sessions may be using it.

## Completion criteria

Finish only when:

- Every actionable review item has a disposition, rationale, action, and proposed local response.
- Accepted items have corresponding unstaged changes.
- Relevant validation has been run or its blocker documented.
- The uniquely named `pr-review-responses-YYYY-MM-DD[-N].md` in the session root contains the original comments and all responses.
- The uniquely named temporary file under `/tmp/<username>/agent` has been deleted, while the shared temporary directory remains.
- Nothing has been posted, staged, committed, or pushed.

In the final user-facing summary, list accepted changes, declined or non-applicable comments, unresolved questions, validation performed, and the response report path.

## Bundled script

Use `scripts/download-pr-reviews.sh` to identify the current branch's LLVM PR and download review summaries and inline comments added since the last locally recorded push. It requires `git`, authenticated `gh`, and `jq`.
