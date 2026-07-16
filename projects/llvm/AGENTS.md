# Overview

This is a working directory for work on the LLVM compiler project.

# Directory Map

This workflow uses one working directory for each task or line of work, so the
workspace root containing this `AGENTS.md` is used for one specific task. Never
read source from a sibling directory unless I tell you to, otherwise you will
read unrelated source.

The workspace root contains the following folders:

- `src/`: LLVM source directory and Git root.
- `src/build/`: Build directory containing tools in `bin/`.
- `local/`: Directory for local-only files, such as test inputs, temporary
  experiments, and bug reproducers. Use this directory if I ask you to summarize
  the current work or findings in a file.

The workflow uses direnv, so when you operate inside the working directory,
necessary PATH and similar setup should already be done.

# Building

This workflow uses CMake and Ninja for building LLVM.

From the workspace root, build with:

```sh
ninja -C src/build <optional-target>
```

If you only need a specific tool, such as `llc`, build that specific target to
avoid excessive build times.

If a tool doesn't exist yet, try to build it.

# Testing

When working on a specific test, run that test directly:

```sh
llvm-lit -sv <path-to-test>
```

Otherwise, run the narrowest appropriate Ninja test target from the workspace
root:

```sh
ninja -C src/build check-<test-target>
```

For example, use `ninja -C src/build check-llvm-codegen` for LLVM CodeGen tests.
Avoid broad test suites when a focused test or test target covers the change.

# Temporary Files

If you need to store temporary files, use `/tmp/$USER/codex`, not `/tmp/`
directly, to avoid conflicts with other people also using agents on this
machine.

# Communication Style

- Be terse and direct. Skip pleasantries and filler.
- Include technical justifications when they're relevant and non-obvious.

# Coding Style

- Correctness over convenience.
- Stick to the LLVM Coding Standards.
- Match the existing style of the file you're editing.
- Avoid code duplication.
- Minimal comments; code should be self-documenting.
- When creating new files, match the existing style for location and naming.

# Version Control

The Git root for this project is `src/`.
