#!/bin/zsh

# ==============================================================================
# Script Name: clean_node.sh
# Description: Recursively finds and deletes node_modules dirs and JS lock files.
# ==============================================================================

# --- Colors ---
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

# --- Defaults ---
DELETE_NODE_MODULES=false
DELETE_LOCKS=false
FORCE=false
DRY_RUN=false
TARGET_DIR="."
MAX_DEPTH=""
EXCLUDE_DIRS=()

LOCK_FILES=("package-lock.json" "bun.lock" "bun.lockb" "pnpm-lock.yaml" "yarn.lock")

# --- Functions ---
usage() {
    cat <<EOF
${BOLD}clean_node${NC} — recursively clean JS/Node dependency artifacts

${BOLD}USAGE${NC}
    clean_node.sh [options]

${BOLD}OPTIONS${NC}
    ${GREEN}-dnm${NC}              Delete node_modules directories
    ${GREEN}-dl${NC}               Delete lock files (package-lock.json, bun.lock,
                      bun.lockb, pnpm-lock.yaml, yarn.lock)
    ${GREEN}-a,  --all${NC}        Delete both node_modules and lock files
    ${GREEN}-f,  --force${NC}      Skip confirmation prompts
    ${GREEN}-n,  --dry-run${NC}    Preview what would be deleted (no actual deletion)
    ${GREEN}-d,  --dir${NC} PATH   Target directory (default: current directory)
    ${GREEN}-e,  --exclude${NC} D  Exclude directory name from search (repeatable)
    ${GREEN}     --max-depth${NC} N Limit recursion depth
    ${GREEN}-h,  --help${NC}       Show this help

${BOLD}EXAMPLES${NC}
    clean_node.sh -dnm                   # delete node_modules, with prompts
    clean_node.sh -dl -f                  # delete lock files, no prompts
    clean_node.sh -a -n                   # dry-run: show everything that would go
    clean_node.sh -dnm -d ~/Projects      # target a specific directory
    clean_node.sh -a -e vendor -e dist    # skip vendor/ and dist/ subtrees
EOF
}

human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" $(( bytes / 1073741824.0 ))
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" $(( bytes / 1048576.0 ))
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" $(( bytes / 1024.0 ))
    else
        printf "%d B" "$bytes"
    fi
}

dir_size_bytes() {
    du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
}

file_size_bytes() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

confirm() {
    local msg="$1"
    if $FORCE; then
        return 0
    fi
    printf "%b [y/N] " "$msg"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -dnm)              DELETE_NODE_MODULES=true ;;
        -dl)               DELETE_LOCKS=true ;;
        -a|--all)          DELETE_NODE_MODULES=true; DELETE_LOCKS=true ;;
        -f|--force)        FORCE=true ;;
        -n|--dry-run)      DRY_RUN=true ;;
        -d|--dir)          TARGET_DIR="$2"; shift ;;
        -e|--exclude)      EXCLUDE_DIRS+=("$2"); shift ;;
        --max-depth)       MAX_DEPTH="$2"; shift ;;
        -h|--help)         usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
    shift
done

# --- Validate ---
if ! $DELETE_NODE_MODULES && ! $DELETE_LOCKS; then
    echo -e "${RED}Error: specify at least one of -dnm, -dl, or -a${NC}\n"
    usage
    exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}Error: directory not found: ${TARGET_DIR}${NC}"
    exit 1
fi

TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

# --- Build find command pieces ---
build_find_args() {
    local args=("$TARGET_DIR")

    if [[ -n "$MAX_DEPTH" ]]; then
        args+=(-maxdepth "$MAX_DEPTH")
    fi

    # Prune excluded dirs and nested node_modules
    local prune_expr=()
    for ex in "${EXCLUDE_DIRS[@]}"; do
        prune_expr+=(-name "$ex" -prune -o)
    done
    if (( ${#prune_expr[@]} > 0 )); then
        args+=("${prune_expr[@]}")
    fi

    echo "${args[@]}"
}

# --- Scan ---
echo -e "${CYAN}${BOLD}Scanning${NC} ${TARGET_DIR} ...\n"

NODE_MODULES_PATHS=()
LOCK_PATHS=()

# Find node_modules (skip nested ones — only top-level per project)
if $DELETE_NODE_MODULES; then
    find_args=("$TARGET_DIR")
    [[ -n "$MAX_DEPTH" ]] && find_args+=(-maxdepth "$MAX_DEPTH")
    for ex in "${EXCLUDE_DIRS[@]}"; do
        find_args+=(-name "$ex" -prune -o)
    done
    find_args+=(-type d -name "node_modules" -prune -print)

    while IFS= read -r dir; do
        NODE_MODULES_PATHS+=("$dir")
    done < <(find "${find_args[@]}" 2>/dev/null)
fi

# Find lock files
if $DELETE_LOCKS; then
    find_args=("$TARGET_DIR")
    [[ -n "$MAX_DEPTH" ]] && find_args+=(-maxdepth "$MAX_DEPTH")
    for ex in "${EXCLUDE_DIRS[@]}"; do
        find_args+=(-name "$ex" -prune -o)
    done
    # Also skip inside node_modules
    find_args+=(-name "node_modules" -prune -o)

    name_expr=()
    for lf in "${LOCK_FILES[@]}"; do
        (( ${#name_expr[@]} > 0 )) && name_expr+=(-o)
        name_expr+=(-name "$lf")
    done
    find_args+=(-type f \( "${name_expr[@]}" \) -print)

    while IFS= read -r f; do
        LOCK_PATHS+=("$f")
    done < <(find "${find_args[@]}" 2>/dev/null)
fi

# --- Nothing found? ---
total_found=$(( ${#NODE_MODULES_PATHS[@]} + ${#LOCK_PATHS[@]} ))
if (( total_found == 0 )); then
    echo -e "${GREEN}Nothing to clean.${NC}"
    exit 0
fi

# --- Report ---
total_bytes=0

if (( ${#NODE_MODULES_PATHS[@]} > 0 )); then
    echo -e "${BOLD}node_modules directories (${#NODE_MODULES_PATHS[@]})${NC}"
    for dir in "${NODE_MODULES_PATHS[@]}"; do
        sz=$(dir_size_bytes "$dir")
        total_bytes=$(( total_bytes + sz ))
        echo -e "  ${DIM}$(human_size $sz)${NC}  $dir"
    done
    echo
fi

if (( ${#LOCK_PATHS[@]} > 0 )); then
    echo -e "${BOLD}Lock files (${#LOCK_PATHS[@]})${NC}"
    for f in "${LOCK_PATHS[@]}"; do
        sz=$(file_size_bytes "$f")
        total_bytes=$(( total_bytes + sz ))
        echo -e "  ${DIM}$(human_size $sz)${NC}  $f"
    done
    echo
fi

echo -e "${CYAN}Total: ${BOLD}$(human_size $total_bytes)${NC}\n"

# --- Dry-run stops here ---
if $DRY_RUN; then
    echo -e "${YELLOW}Dry-run mode — nothing was deleted.${NC}"
    exit 0
fi

# --- Delete ---
deleted_bytes=0
deleted_count=0
skipped_count=0

for dir in "${NODE_MODULES_PATHS[@]}"; do
    sz=$(dir_size_bytes "$dir")
    if confirm "${RED}Delete${NC} $dir ${DIM}($(human_size $sz))${NC}?"; then
        rm -rf "$dir"
        echo -e "  ${GREEN}[✔] Deleted${NC}"
        deleted_bytes=$(( deleted_bytes + sz ))
        (( deleted_count++ ))
    else
        echo -e "  ${YELLOW}[—] Skipped${NC}"
        (( skipped_count++ ))
    fi
done

for f in "${LOCK_PATHS[@]}"; do
    sz=$(file_size_bytes "$f")
    if confirm "${RED}Delete${NC} $f ${DIM}($(human_size $sz))${NC}?"; then
        rm -f "$f"
        echo -e "  ${GREEN}[✔] Deleted${NC}"
        deleted_bytes=$(( deleted_bytes + sz ))
        (( deleted_count++ ))
    else
        echo -e "  ${YELLOW}[—] Skipped${NC}"
        (( skipped_count++ ))
    fi
done

# --- Summary ---
echo
echo -e "${BOLD}Done.${NC}"
echo -e "  Deleted: ${GREEN}${deleted_count}${NC} items  ($(human_size $deleted_bytes) freed)"
if (( skipped_count > 0 )); then
    echo -e "  Skipped: ${YELLOW}${skipped_count}${NC} items"
fi
