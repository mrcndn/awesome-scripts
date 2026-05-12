# clean_zsh_history

Wipes Zsh history and sessions, optionally restoring preferred commands from a backup file (`~/.zsh_preferred_commands`).

## Usage

```bash
runscript clean_zsh_history
```

## What it does

1. Deletes `~/.zsh_history`
2. Removes `~/.zsh_sessions` directory
3. Restores preferred commands from `~/.zsh_preferred_commands` (if exists)
4. Sets strict permissions (600) on the new history file
5. Reloads history for the current session (if sourced)
