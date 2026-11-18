#!/usr/bin/env zsh

source "$AGENT_SETUP_DIR/configs/lib.sh" || return 1

install_skill() {
  local source_path="$1"
  local name="${2:-${source_path:t}}"

  install_symlink "$source_path" "$AGENT_SETUP_TARGET/.agents/skills/$name"
}

install_agent() {
  local source_path="$1"
  local name="${2:-${source_path:t}}"

  install_symlink "$source_path" "$AGENT_SETUP_TARGET/.codex/agents/$name"
}

install_config() {
  local source_path="$1"

  install_symlink "$source_path" "$AGENT_SETUP_TARGET/AGENTS.md"
}
