#!/usr/bin/env zsh

install_symlink() {
  local source_path="$1"
  local destination_path="$2"
  local destination_dir="${destination_path:h}"

  if [[ ! -e "$source_path" ]]; then
    echo "Error: symlink source does not exist: $source_path" >&2
    return 1
  fi

  source_path="${source_path:A}"
  mkdir -p "$destination_dir" || return 1

  if [[ -L "$destination_path" ]]; then
    ln -sfn "$source_path" "$destination_path" || return 1
    echo "Linked $destination_path -> $source_path"
    return 0
  fi

  if [[ -e "$destination_path" ]]; then
    echo "Error: refusing to replace existing non-symlink path: $destination_path" >&2
    return 1
  fi

  ln -s "$source_path" "$destination_path" || return 1
  echo "Linked $destination_path -> $source_path"
}

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
