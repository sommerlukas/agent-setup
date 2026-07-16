#!/usr/bin/env zsh

set -o pipefail

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  NC=$'\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

error() {
  echo "${RED}Error:${NC} $1" >&2
  exit "${2:-1}"
}

warn() {
  echo "${YELLOW}Warning:${NC} $1" >&2
}

success() {
  echo "${GREEN}$1${NC}"
}

validate_identifier() {
  local kind="$1"
  local value="$2"

  if [[ -z "$value" || "$value" == *[^A-Za-z0-9._-]* ]]; then
    error "Invalid $kind '$value'. Use only letters, numbers, dots, underscores, and hyphens." 2
  fi
}

get_state_dir() {
  echo "${XDG_DATA_HOME:-$HOME/.local/share}/agent-setup"
}

get_installed_agents_file() {
  echo "$(get_state_dir)/installed-agents"
}

is_agent_installed() {
  local agent="$1"
  local state_file
  state_file=$(get_installed_agents_file)

  [[ -f "$state_file" ]] && grep -Fxq -- "$agent" "$state_file"
}

mark_agent_installed() {
  local agent="$1"
  local state_dir
  local state_file
  local temp_file

  state_dir=$(get_state_dir)
  state_file=$(get_installed_agents_file)
  mkdir -p "$state_dir" || return 1

  if is_agent_installed "$agent"; then
    return 0
  fi

  temp_file="${state_file}.tmp.$$"
  {
    [[ -f "$state_file" ]] && cat "$state_file"
    echo "$agent"
  } >"$temp_file" || {
    rm -f "$temp_file"
    return 1
  }

  mv "$temp_file" "$state_file"
}

default_config_hook() {
  local target_path="$1"
  local agent="$2"
  local project_config_dir="$PWD"
  local config_file="$project_config_dir/AGENTS.md"
  local asset_dir
  local asset
  local -a assets

  if [[ -f "$config_file" ]]; then
    typeset -f install_config >/dev/null || {
      echo "Error: agent '$agent' does not provide install_config" >&2
      return 1
    }
    install_config "$config_file" || return 1
  fi

  asset_dir="$project_config_dir/agents"
  if [[ -d "$asset_dir" ]]; then
    assets=("$asset_dir"/*(N))
    if (( ${#assets[@]} > 0 )); then
      typeset -f install_agent >/dev/null || {
        echo "Error: agent '$agent' does not provide install_agent" >&2
        return 1
      }
      for asset in "${assets[@]}"; do
        install_agent "$asset" "${asset:t}" || return 1
      done
    fi
  fi

  asset_dir="$project_config_dir/skills"
  if [[ -d "$asset_dir" ]]; then
    assets=("$asset_dir"/*(N))
    if (( ${#assets[@]} > 0 )); then
      typeset -f install_skill >/dev/null || {
        echo "Error: agent '$agent' does not provide install_skill" >&2
        return 1
      }
      for asset in "${assets[@]}"; do
        install_skill "$asset" "${asset:t}" || return 1
      done
    fi
  fi
}

run_setup_hook() {
  local agent="$1"
  local config_dir="$AGENT_SETUP_DIR/configs/$agent"
  local setup_script="$config_dir/setup.sh"

  [[ -d "$config_dir" ]] || error "Unknown agent '$agent': $config_dir does not exist" 2
  [[ -f "$setup_script" ]] || error "Agent '$agent' does not provide setup.sh" 2

  (
    export AGENT_SETUP_AGENT="$agent"
    unset AGENT_SETUP_PROJECT AGENT_SETUP_TARGET
    cd "$config_dir" || exit 1
    source "$setup_script" || exit 1
    typeset -f setup_hook >/dev/null || {
      echo "Error: $setup_script does not define setup_hook" >&2
      exit 2
    }
    setup_hook
  )
}

cmd_setup() {
  if [[ $# -ne 1 ]]; then
    error "Usage: agent-setup setup <agent>" 2
  fi

  local agent="$1"
  validate_identifier "agent name" "$agent"

  echo "Setting up agent '$agent'..."
  run_setup_hook "$agent" || error "Setup failed for agent '$agent'"
  mark_agent_installed "$agent" || error "Failed to record setup state for agent '$agent'"

  success "Agent '$agent' setup completed successfully."
}

cmd_config() {
  if [[ $# -lt 1 || $# -gt 3 ]]; then
    error "Usage: agent-setup config <project> [agent] [path]" 2
  fi

  local project="$1"
  local agent="${2:-codex}"
  local target="${3:-$PWD}"
  local agent_dir
  local project_dir
  local hooks_script
  local config_script

  validate_identifier "project name" "$project"
  validate_identifier "agent name" "$agent"

  [[ -d "$target" ]] || error "Project target is not a directory: $target" 2
  target=$(realpath "$target") || error "Cannot resolve project target: $target"

  agent_dir="$AGENT_SETUP_DIR/configs/$agent"
  project_dir="$AGENT_SETUP_DIR/projects/$project"
  hooks_script="$agent_dir/hooks.sh"
  config_script="$project_dir/config.sh"

  [[ -d "$agent_dir" ]] || error "Unknown agent '$agent': $agent_dir does not exist" 2
  [[ -f "$hooks_script" ]] || error "Agent '$agent' does not provide hooks.sh" 2
  [[ -d "$project_dir" ]] || error "Unknown project '$project': $project_dir does not exist" 2
  [[ -f "$config_script" ]] || error "Project '$project' does not provide config.sh" 2

  echo "Configuring project '$project' for agent '$agent' at $target..."
  (
    export AGENT_SETUP_AGENT="$agent"
    export AGENT_SETUP_PROJECT="$project"
    export AGENT_SETUP_TARGET="$target"
    cd "$project_dir" || exit 1
    source "$hooks_script" || exit 1
    source "$config_script" || exit 1
    typeset -f config_hook >/dev/null || {
      echo "Error: $config_script does not define config_hook" >&2
      exit 2
    }
    config_hook "$target" "$agent"
  ) || error "Configuration failed for project '$project' and agent '$agent'"

  success "Project '$project' configured successfully for agent '$agent'."
}

changed_config_agents() {
  local old_revision="$1"
  local new_revision="$2"

  git diff --name-only "$old_revision" "$new_revision" -- configs |
    while IFS= read -r path; do
      if [[ "$path" == configs/*/* ]]; then
        local remainder="${path#configs/}"
        echo "${remainder%%/*}"
      fi
    done |
    sort -u
}

cmd_update() {
  if [[ $# -ne 0 ]]; then
    error "Usage: agent-setup update" 2
  fi

  [[ -d "$AGENT_SETUP_DIR" ]] || error "Installation directory not found: $AGENT_SETUP_DIR"
  cd "$AGENT_SETUP_DIR" || error "Cannot access installation directory"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || error "Installation directory is not a Git repository"

  if [[ -n "$(git status --porcelain)" ]]; then
    error "Local modifications detected. Commit or stash them before updating."
  fi

  local upstream
  upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) ||
    error "No upstream tracking branch is configured"

  local unpushed
  unpushed=$(git rev-list --count "${upstream}..HEAD") || error "Failed to inspect local commits"
  if (( unpushed > 0 )); then
    error "Local commits have not been pushed. Push or remove them before updating."
  fi

  local old_revision
  old_revision=$(git rev-parse HEAD) || error "Failed to determine current revision"

  echo "Fetching updates..."
  git fetch --quiet || error "Failed to fetch updates"

  local behind
  behind=$(git rev-list --count "HEAD..${upstream}") || error "Failed to compare with upstream"
  if (( behind == 0 )); then
    success "Agent setup is already up to date."
    return 0
  fi

  echo "Installing $behind new commit(s)..."
  git merge --ff-only --quiet "$upstream" || error "Update is not a fast-forward"

  local new_revision
  new_revision=$(git rev-parse HEAD) || error "Failed to determine updated revision"

  local -a agents_to_setup
  local agent
  while IFS= read -r agent; do
    [[ -n "$agent" ]] || continue
    if is_agent_installed "$agent"; then
      agents_to_setup+=("$agent")
    fi
  done < <(changed_config_agents "$old_revision" "$new_revision")

  if (( ${#agents_to_setup[@]} == 0 )); then
    success "Agent setup updated successfully."
    return 0
  fi

  echo "Reapplying updated configuration for installed agents..."
  local failed=0
  for agent in "${agents_to_setup[@]}"; do
    echo "  Setting up '$agent'..."
    if "$AGENT_SETUP_DIR/agent-setup.sh" setup "$agent"; then
      success "  Setup completed for '$agent'."
    else
      warn "  Setup failed for '$agent'."
      failed=1
    fi
  done

  if (( failed != 0 )); then
    error "Agent setup updated, but one or more agent setup hooks failed"
  fi

  success "Agent setup updated successfully."
}

cmd_help() {
  if [[ $# -ne 0 ]]; then
    error "Usage: agent-setup help" 2
  fi

  cat <<'EOF'
Agent Setup

Usage:
  agent-setup setup <agent>
  agent-setup config <project> [agent] [path]
  agent-setup update
  agent-setup help

Commands:
  setup   Run configs/<agent>/setup.sh and record a successful setup.
  config  Configure a project using an agent's hooks. The agent defaults to
          'codex' and the target path defaults to the current directory.
  update  Safely update this installation and rerun changed configurations for
          agents that have previously completed setup.
  help    Show this message.
EOF
}

main() {
  command -v git >/dev/null 2>&1 || error "git is required but was not found in PATH"

  if [[ -z "${AGENT_SETUP_DIR:-}" ]]; then
    local script_path="${0:A}"
    export AGENT_SETUP_DIR="${script_path:h}"
  else
    export AGENT_SETUP_DIR
  fi

  local command="${1:-help}"
  shift || true

  case "$command" in
    setup)
      cmd_setup "$@"
      ;;
    config)
      cmd_config "$@"
      ;;
    update)
      cmd_update "$@"
      ;;
    help|--help|-h)
      cmd_help "$@"
      ;;
    *)
      error "Unknown command '$command'. Run 'agent-setup help' for usage." 2
      ;;
  esac
}

main "$@"
