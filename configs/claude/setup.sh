#!/usr/bin/env zsh

configure_allow_write() {
  local settings_file="$1"
  local allowed_path="$2"
  local settings_dir="${settings_file:h}"
  local temporary_file

  command -v jq >/dev/null || {
    echo "Error: jq is required to update $settings_file" >&2
    return 1
  }

  mkdir -p "$settings_dir" || return 1
  [[ -s "$settings_file" ]] || echo '{}' >"$settings_file" || return 1
  temporary_file=$(mktemp "$settings_dir/.settings.json.XXXXXX") || return 1

  if ! jq --arg allowed_path "$allowed_path" '
    .sandbox.filesystem.allowWrite = (
      ((.sandbox.filesystem.allowWrite // []) + [$allowed_path]) | unique
    )
  ' "$settings_file" >"$temporary_file"; then
    rm -f "$temporary_file"
    echo "Error: could not update $settings_file (invalid JSON?)" >&2
    return 1
  fi

  if cmp -s "$settings_file" "$temporary_file"; then
    rm -f "$temporary_file"
    return 0
  fi

  chmod --reference="$settings_file" "$temporary_file" 2>/dev/null || true
  mv "$temporary_file" "$settings_file"
}

setup_hook() {
  local username
  local user_id
  local settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  local -a writable_paths
  local writable_path

  username="${USER:-$(id -un)}"
  user_id=$(id -u) || return 1
  writable_paths=(
    "/tmp/$username/agent"
    "$HOME/.ccache"
    "/run/user/$user_id/ccache-tmp"
  )

  for writable_path in "${writable_paths[@]}"; do
    echo "Creating Claude Code writable directory at $writable_path..."
    mkdir -p "$writable_path" || return 1

    echo "Allowing Claude Code sandbox write access to $writable_path..."
    configure_allow_write "$settings_file" "$writable_path" || return 1
  done

  echo "Claude Code setup finished."
}
