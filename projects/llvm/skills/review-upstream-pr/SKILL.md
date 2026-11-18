---
name: review-upstream-pr
description: Review an upstream llvm/llvm-project pull request for logic errors, regressions, missing tests, and LLVM coding-standard violations. Use when asked to review, assess, or provide code-review comments for a numbered upstream LLVM PR (e.g. "review PR 12345"). Downloads and retains the PR diff, keeps the checkout unchanged, summarizes findings in chat, and writes concrete local review comments.
---

# Review Upstream PR

Review a numbered `llvm/llvm-project` pull request without modifying the local
checkout or posting feedback to GitHub.

## Workflow

1. Establish the workspace and PR.
   - Capture the initial workspace root before changing directories:

     ```bash
     workspace_root="$(pwd -P)"
     ```

   - Require a positive numeric PR number.
   - Confirm that `src/` is an LLVM Git checkout.
   - Preserve the working tree exactly as it is. Do not fetch, checkout, apply,
     edit, stage, commit, push, or post GitHub comments.

2. Download the upstream diff.
   - Resolve this skill's directory from the loaded `SKILL.md`.
   - Run:

     ```bash
     review_paths="$(
       <skill-directory>/scripts/download-pr-diff.sh \
         "<pr-number>" "$workspace_root"
     )
     diff_file="${review_paths%%$'\n'*}"
     report_file="${review_paths#*$'\n'}"
     ```

   - The script selects the first positive suffix unused by both the retained
     diff and report paths. It downloads from the full upstream GitHub PR URL,
     writes the diff under `/tmp/$USER/agent`, and prints the paired absolute
     paths.
   - Require exactly two output lines and verify that `diff_file` is readable.
   - Read the complete diff before assessing individual changes.

3. Understand the change.
   - Summarize the intent and enumerate the changed components.
   - Inspect relevant files in `src/` and local Git history for context.
   - Treat the downloaded diff as authoritative when the local checkout differs
     from the PR.
   - Do not change the checkout to obtain more context.

4. Review the diff.
   - Prioritize correctness over style.
   - Look for logic errors, behavioral regressions, invalid assumptions,
     lifetime or ownership bugs, error-handling gaps, concurrency problems,
     portability issues, and missing or inadequate tests.
   - Identify concrete violations of the LLVM Coding Standards or the existing
     style of the affected file.
   - Do not report speculative concerns without a reproducible failure mode or
     a clear violated invariant.
   - Avoid low-value stylistic preferences.

5. Write the Markdown report.
   - Write to `report_file` without overwriting an existing path.
   - Include:
     - PR number and upstream URL;
     - retained diff path;
     - a concise overview of the change;
     - findings ordered by severity.
   - Use this structure for every finding:

     ````markdown
     ## [P1|P2|P3] Concise finding title

     **Location:** `path/to/file.cpp:123` (new side)

     ```diff
     smallest relevant diff hunk
     ```

     Concrete reviewer comment explaining the failure mode, why it matters,
     and the required direction for a fix.
     ````

   - Use a new-side line number for additions or unchanged context. Use an
     old-side line number and label it `old side` for deletion-only findings.
   - Keep each comment independently understandable and suitable for posting
     as a GitHub review comment.
   - If there are no actionable findings, include `No actionable findings.`
   - Keep the downloaded diff; it is intentionally retained for future review.

6. Report the result in chat.
   - List findings first, ordered by severity, with file and line references.
   - If there are no findings, say so directly and mention any residual
     validation limitations.
   - Provide the absolute report and retained diff paths.
   - Do not post, stage, commit, push, or modify source files.

## Severity

- `P1`: likely serious miscompilation, crash, data loss, security issue, or
  broadly blocking regression.
- `P2`: concrete correctness or maintainability defect that should be fixed
  before landing.
- `P3`: localized issue or concrete coding-standard violation with limited
  impact.

## Completion Criteria

Finish only when the complete diff has been reviewed, every finding has a
precise diff location and concrete comment, the uniquely named report exists
under `local/`, the retained diff exists under `/tmp/$USER/agent`, and the
checkout remains unchanged.
