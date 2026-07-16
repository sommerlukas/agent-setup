#!/usr/bin/env zsh

configure_writable_root() {
  local config_file="$1"
  local writable_root="$2"
  local config_dir="${config_file:h}"
  local temporary_file

  mkdir -p "$config_dir" || return 1
  [[ -f "$config_file" ]] || : >"$config_file"
  temporary_file=$(mktemp "$config_dir/.config.toml.XXXXXX") || return 1

  awk -v root="$writable_root" '
    function emit_root() {
      print "writable_roots = [\"" root "\"]"
    }

    function is_section(line) {
      return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/
    }

    function is_target_section(line) {
      return line ~ /^[[:space:]]*\[sandbox_workspace_write\][[:space:]]*(#.*)?$/
    }

    function has_root(block) {
      return index(block, "\"" root "\"") || index(block, "\047" root "\047")
    }

    function last_index(text, character, position) {
      for (position = length(text); position > 0; position--) {
        if (substr(text, position, 1) == character) {
          return position
        }
      }
      return 0
    }

    function add_root(block, opening, closing, before, inside, after) {
      opening = index(block, "[")
      closing = last_index(block, "]")
      if (!opening || !closing || closing < opening) {
        print "Error: writable_roots must be a TOML array" >"/dev/stderr"
        exit 2
      }

      before = substr(block, 1, opening)
      inside = substr(block, opening + 1, closing - opening - 1)
      after = substr(block, closing)

      if (inside ~ /^[[:space:]]*$/) {
        return before "\"" root "\"" after
      }
      return before "\"" root "\", " inside after
    }

    {
      if (is_target_section($0)) {
        if (in_target && !found_key) {
          emit_root()
        }
        found_section = 1
        in_target = 1
        found_key = 0
        print
        next
      }

      if (is_section($0)) {
        if (in_target && !found_key) {
          emit_root()
        }
        in_target = 0
        print
        next
      }

      if (in_target && $0 ~ /^[[:space:]]*writable_roots[[:space:]]*=/) {
        block = $0
        while (last_index(block, "]") < index(block, "[")) {
          if ((getline line) <= 0) {
            print "Error: writable_roots array is not terminated" >"/dev/stderr"
            exit 2
          }
          block = block "\n" line
        }

        found_key = 1
        if (has_root(block)) {
          print block
        } else {
          print add_root(block)
        }
        next
      }

      print
    }

    END {
      if (in_target && !found_key) {
        emit_root()
      } else if (!found_section) {
        print ""
        print "[sandbox_workspace_write]"
        emit_root()
      }
    }
  ' "$config_file" >"$temporary_file"
  local awk_status=$?

  if [[ "$awk_status" -ne 0 ]]; then
    rm -f "$temporary_file"
    return "$awk_status"
  fi

  if cmp -s "$config_file" "$temporary_file"; then
    rm -f "$temporary_file"
    return 0
  fi

  chmod --reference="$config_file" "$temporary_file" 2>/dev/null || true
  mv "$temporary_file" "$config_file"
}

setup_hook() {
  local username
  local user_id
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local config_file="$codex_home/config.toml"
  local -a writable_roots
  local writable_root

  username="${USER:-$(id -un)}"
  user_id=$(id -u) || return 1
  writable_roots=(
    "/tmp/$username/codex"
    "$HOME/.ccache"
    "/run/user/$user_id/ccache-tmp"
  )

  for writable_root in "${writable_roots[@]}"; do
    echo "Creating Codex writable directory at $writable_root..."
    mkdir -p "$writable_root" || return 1

    echo "Allowing Codex workspace-write access to $writable_root..."
    configure_writable_root "$config_file" "$writable_root" || return 1
  done

  echo "Codex setup finished."
}
