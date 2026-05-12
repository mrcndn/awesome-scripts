# clean_node

Recursively finds and deletes `node_modules` directories and JS lock files.

## Usage

```bash
runscript clean_node [options]
```

## Options

| Flag | Description |
|------|-------------|
| `-dnm` | Delete node_modules directories |
| `-dl` | Delete lock files (package-lock.json, bun.lock, bun.lockb, pnpm-lock.yaml, yarn.lock) |
| `-a, --all` | Delete both node_modules and lock files |
| `-f, --force` | Skip confirmation prompts |
| `-n, --dry-run` | Preview what would be deleted |
| `-d, --dir PATH` | Target directory (default: current directory) |
| `-e, --exclude D` | Exclude directory name from search (repeatable) |
| `--max-depth N` | Limit recursion depth |

## Examples

```bash
runscript clean_node -dnm                   # delete node_modules, with prompts
runscript clean_node -dl -f                  # delete lock files, no prompts
runscript clean_node -a -n                   # dry-run: show everything
runscript clean_node -dnm -d ~/Projects      # target a specific directory
runscript clean_node -a -e vendor -e dist    # skip vendor/ and dist/ subtrees
```
