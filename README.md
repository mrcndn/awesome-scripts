# Awesome Scripts

A collection of useful scripts to automate daily tasks and improve productivity.

## Installation

```bash
git clone https://github.com/mrcndn/awesome-scripts.git
cd awesome-scripts
./install.sh
```

After installation, use `runscript` to run any script by name:

```bash
runscript clean_node -a --dry-run
runscript system_info
```

Run `runscript` without arguments to see all available scripts.

## Scripts

### Clean Node (`sh/clean_node.sh`)
Recursively finds and deletes `node_modules` directories and JS lock files (`package-lock.json`, `bun.lock`, `pnpm-lock.yaml`, `yarn.lock`). Supports dry-run, directory targeting, exclusions, and depth limiting.

### Node Secure (`sh/node_secure.sh`)
3-layer supply-chain security hardening for Node.js projects. Supports npm, bun, pnpm, and yarn.

- **Layer 1**: Install-time protection — `minimumReleaseAge` config, dependency pinning (strip `^`/`~`), `save-exact`, lockfile commit check
- **Layer 2**: Pre-commit hooks — installs lefthook with audit-on-lock-change hooks
- **Layer 3**: Scheduled scanning — daily audit via launchd (macOS) or systemd timer (Linux) with desktop notifications

```bash
runscript node_secure --check-only -d ~/Projects   # report only
runscript node_secure --all --dry-run               # preview changes
runscript node_secure --layer1 --audit              # apply + audit
```

### Clean Zsh History (`sh/clean_zsh_history.sh`)
Wipes Zsh history and sessions, optionally restoring preferred commands from a backup file.

### Delete History (`sh/delete_history.sh`)
Safely clears bash history or specific lines to maintain privacy.

### System Info (`sh/system_info.sh`)
Displays basic system information including OS, Kernel, Uptime, and Memory usage.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
