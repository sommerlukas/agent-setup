# Agent Setup

A small zsh-based command-line tool for installing and maintaining coding-agent
configuration across projects.

The repository separates reusable agent behavior from project-specific
configuration:

```text
agent-setup/
├── agent-setup.sh
├── bootstrap.sh
├── configs/
│   └── <agent>/
│       ├── setup.sh
│       └── hooks.sh
└── projects/
    └── <project>/
        ├── AGENTS.md
        ├── agents/
        ├── skills/
        └── config.sh
```

## Installation

Install the repository with:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/sommerlukas/agent-setup/main/bootstrap.sh)"
```

The bootstrap script:

- clones the repository to `~/.agent-setup`;
- creates the state directory at `~/.local/share/agent-setup`;
- exports `AGENT_SETUP_DIR` from `~/.zshrc`; and
- adds the `agent-setup` alias.

Reload zsh after installation:

```zsh
source ~/.zshrc
```

To bootstrap from another Git repository:

```sh
./bootstrap.sh https://github.com/example/agent-setup.git
```

## Commands

### Set up an agent

```zsh
agent-setup setup <agent>
```

This loads `configs/<agent>/setup.sh`, invokes `setup_hook`, and records the
agent as installed only if the hook succeeds.

Successfully configured agents are stored one per line in:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/agent-setup/installed-agents
```

### Configure a project

```zsh
agent-setup config <project>
agent-setup config <project> <agent>
agent-setup config <project> <agent> /path/to/project
```

The agent defaults to `codex`, and the target path defaults to the current
directory. The command loads the agent hooks first, then invokes the project's
`config_hook`.

### Update the installation

```zsh
agent-setup update
```

Update requires:

- a clean installation checkout;
- an upstream tracking branch; and
- no unpushed local commits.

The update is applied as a fast-forward. If files below
`configs/<agent>/` changed and that agent previously completed setup, the
updated CLI reruns `setup <agent>`. All affected agents are attempted, and the
command exits unsuccessfully if any setup hook fails.

## Extension API

Agent names and project names may contain letters, numbers, dots, underscores,
and hyphens.

### Agent setup

`configs/<agent>/setup.sh` must define:

```zsh
setup_hook() {
  # Perform user-level installation and basic configuration.
}
```

The hook runs from `configs/<agent>/`.

### Agent project hooks

`configs/<agent>/hooks.sh` can provide:

```zsh
install_skill() {
  local source="$1"
  local name="${2:-}"
}

install_agent() {
  local source="$1"
  local name="${2:-}"
}

install_config() {
  local source="$1"
}
```

The exact destination and replacement policy belong to the agent
implementation.

### Project configuration

`projects/<project>/config.sh` must define:

```zsh
config_hook() {
  default_config_hook "$@"
}
```

Agent hooks are loaded before `config_hook`. Project hooks run from the
project's configuration directory.

The built-in `default_config_hook` supports this layout:

```text
projects/<project>/
├── AGENTS.md
├── agents/
│   └── <agent-entry>
└── skills/
    └── <skill-entry>/
        └── SKILL.md
```

Every element is optional. When present, `AGENTS.md` is passed to
`install_config`. Each immediate entry under `agents/` is passed to
`install_agent`, and each immediate entry under `skills/` is passed to
`install_skill`. Asset hooks receive the full source path and the entry's base
name. Empty or absent asset directories require no corresponding hook.

Projects can invoke installation hooks directly when they need behavior beyond
the default layout. See `projects/example/` for a complete generic example.

The following variables are exported while hooks execute:

- `AGENT_SETUP_DIR`
- `AGENT_SETUP_AGENT`
- `AGENT_SETUP_PROJECT` during project configuration
- `AGENT_SETUP_TARGET` during project configuration

Hooks run in subshells, so shell functions and directory changes do not leak
back into the CLI.

## Development

Run syntax checks and integration tests with:

```sh
zsh -n agent-setup.sh configs/*/*.sh projects/*/config.sh
sh -n bootstrap.sh
tests/integration.sh
```
