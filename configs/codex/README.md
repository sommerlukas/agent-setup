# Codex Configuration

## User setup

The setup hook creates and grants workspace-write access to:

- `/tmp/<username>/codex`;
- `$HOME/.ccache`; and
- `/run/user/<uid>/ccache-tmp`.

These paths are added to `sandbox_workspace_write.writable_roots` in
`${CODEX_HOME:-$HOME/.codex}/config.toml`. Existing roots and unrelated settings
are preserved, and repeated setup runs do not add duplicate entries.

## Project hooks

Project configuration is installed using absolute symbolic links:

- `AGENTS.md` is linked to `<target>/AGENTS.md`;
- agent entries are linked individually under `<target>/.codex/agents/`; and
- skill entries are linked individually under `<target>/.agents/skills/`.

Rerunning project configuration refreshes existing symlinks. The hooks refuse
to replace an existing real file or directory at a destination.
