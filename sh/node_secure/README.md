# node_secure

3-layer supply-chain security hardening for Node.js projects. Supports npm, bun, pnpm, and yarn.

## Layers

| Layer | What it does |
|-------|-------------|
| **Layer 1** | Install-time protection: `minimumReleaseAge` config, dependency pinning (strip `^`/`~`), `save-exact`, global `~/.npmrc` + `~/.bunfig.toml` |
| **Layer 2** | Pre-commit hooks: installs lefthook with audit-on-lock-change (pre-commit `high`, pre-push `moderate`) |
| **Layer 3** | Scheduled scanning: daily audit via launchd (macOS) or systemd timer (Linux) with desktop notifications |

## Usage

```bash
runscript node_secure [options]
```

Running without flags defaults to `--check-only` with all layers reported.

## Options

| Flag | Description |
|------|-------------|
| `--layer1` | Apply Layer 1 only |
| `--layer2` | Apply Layer 2 only |
| `--layer3` | Apply Layer 3 only |
| `-a, --all` | Apply all three layers |
| `--age N` | Minimum release age in days (default: 7) |
| `--audit` | Run security audit for each project |
| `--check-only` | Only report status, no modifications |
| `-n, --dry-run` | Preview what would change |
| `-f, --force` | Skip confirmation prompts and interactive selector |
| `-d, --dir PATH` | Target directory (default: current directory) |
| `-e, --exclude D` | Exclude directory name (repeatable) |
| `--max-depth N` | Limit recursion depth |

## Examples

```bash
runscript node_secure --check-only -d ~/Projects   # report only
runscript node_secure --all --dry-run               # preview all changes
runscript node_secure --layer1 --audit              # apply layer 1 + audit
runscript node_secure --all --age 3 -f              # apply all, 3-day age, no prompts
```

## How it works

Most npm supply-chain attacks (Axios, Solana web3.js, ua-parser-js, Ledger Connect Kit) are detected and removed within hours. `minimumReleaseAge` blocks packages published too recently, filtering out the vast majority of these attacks automatically.

### Config per package manager

| PM | Config file | Key | Unit | 7-day value |
|----|------------|-----|------|-------------|
| npm | `.npmrc` | `min-release-age` | days | `7` |
| bun | `bunfig.toml` | `minimumReleaseAge` | seconds | `604800` |
| pnpm | `pnpm-workspace.yaml` / `.npmrc` | `minimumReleaseAge` | minutes | `10080` |
| yarn | `.yarnrc.yml` | `npmMinimalAgeGate` | minutes | `10080` |
