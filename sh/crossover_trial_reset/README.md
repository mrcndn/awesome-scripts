# crossover_trial_reset

Resets CrossOver trial license data and bottle timestamps. Can run once or install as a recurring macOS launchd service.

## Usage

```bash
runscript crossover_trial_reset [execute|install|uninstall]
```

| Argument | Description |
|----------|-------------|
| `execute` | Reset trial dates and bottles once |
| `install` | Reset + install as recurring launchd service |
| `uninstall` | Remove the launchd service and script directory |

Running without arguments prompts for a choice.
