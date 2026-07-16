#!/bin/sh

set -e

INSTALL_DIR="${AGENT_SETUP_INSTALL_DIR:-$HOME/.agent-setup}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
DEFAULT_REPO_URL="https://github.com/sommerlukas/agent-setup.git"

error() {
  echo "Error: $1" >&2
  exit 1
}

info() {
  echo "$1"
}

main() {
  repo_url="${1:-$DEFAULT_REPO_URL}"

  if [ "$#" -gt 1 ]; then
    error "Usage: bootstrap.sh [repository-url]"
  fi

  if [ -e "$INSTALL_DIR" ]; then
    error "Installation path already exists: $INSTALL_DIR"
  fi

  command -v git >/dev/null 2>&1 || error "git is required but was not found in PATH"

  info "Cloning agent setup from $repo_url..."
  git clone "$repo_url" "$INSTALL_DIR" || error "Failed to clone repository"

  chmod +x "$INSTALL_DIR/agent-setup.sh" "$INSTALL_DIR/bootstrap.sh"
  mkdir -p "$HOME/.local/share/agent-setup"

  if [ ! -f "$ZSHRC" ]; then
    mkdir -p "$(dirname "$ZSHRC")"
    touch "$ZSHRC"
  fi

  if ! grep -q '^# Agent Setup$' "$ZSHRC"; then
    cat >>"$ZSHRC" <<'EOF'

# Agent Setup
export AGENT_SETUP_DIR="$HOME/.agent-setup"
alias agent-setup="$AGENT_SETUP_DIR/agent-setup.sh"
EOF
  fi

  info ""
  info "Agent setup installed successfully."
  info "Reload your shell with: source \"$ZSHRC\""
  info "Then run: agent-setup help"
}

main "$@"

