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

Each script lives in its own directory under `sh/` with its own README.

| Script | Description |
|--------|-------------|
| [clean_node](sh/clean_node/) | Recursively delete `node_modules` and lock files |
| [node_secure](sh/node_secure/) | 3-layer supply-chain security hardening (npm, bun, pnpm, yarn) |
| [clean_zsh_history](sh/clean_zsh_history/) | Wipe Zsh history and sessions |
| [delete_history](sh/delete_history/) | Clear bash history (all or last N lines) |
| [system_info](sh/system_info/) | Display basic system information |

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
