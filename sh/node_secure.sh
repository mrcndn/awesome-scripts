#!/bin/zsh

# ==============================================================================
# Script Name: node_secure.sh
# Description: 3-layer Node.js supply-chain security hardening.
#              Supports npm, bun, pnpm, and yarn.
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
LAYER1=false
LAYER2=false
LAYER3=false
RUN_AUDIT=false
CHECK_ONLY=false
DRY_RUN=false
FORCE=false
TARGET_DIR="."
MAX_DEPTH=""
EXCLUDE_DIRS=()
AGE_DAYS=7

# --- Counters ---
projects_found=0
applied_count=0
skipped_count=0
audit_clean=0
audit_vuln=0

# --- Collected work ---
NEED_RELEASE_AGE=()
NEED_PIN=()
NEED_LEFTHOOK=()
PROJECT_LIST=()
PROJECT_PM_LIST=()

# ============================= Utility ========================================

usage() {
    cat <<EOF
${BOLD}node_secure${NC} — 3-layer Node.js supply-chain security hardening

${BOLD}USAGE${NC}
    node_secure.sh [options]

${BOLD}LAYERS${NC}
    ${GREEN}--layer1${NC}           Install-time protection (release age, pinned deps)
    ${GREEN}--layer2${NC}           Pre-commit hooks (lefthook + audit on lock change)
    ${GREEN}--layer3${NC}           Scheduled daily audit scan (launchd / systemd)
    ${GREEN}-a,  --all${NC}         Apply all three layers

${BOLD}OPTIONS${NC}
    ${GREEN}     --age${NC} N        Minimum release age in days (default: 7)
    ${GREEN}     --audit${NC}        Run security audit for each project
    ${GREEN}     --check-only${NC}   Only report status, do not modify anything
    ${GREEN}-n,  --dry-run${NC}      Preview what would change (no modifications)
    ${GREEN}-f,  --force${NC}        Skip confirmation prompts
    ${GREEN}-d,  --dir${NC} PATH     Target directory (default: current directory)
    ${GREEN}-e,  --exclude${NC} D    Exclude directory name from search (repeatable)
    ${GREEN}     --max-depth${NC} N   Limit recursion depth
    ${GREEN}-h,  --help${NC}         Show this help

${BOLD}EXAMPLES${NC}
    node_secure.sh --check-only -d ~/Projects
    node_secure.sh --layer1 --dry-run -d ~/Projects
    node_secure.sh --all -f -d ~/Projects
    node_secure.sh --layer2 --audit
    node_secure.sh --all --age 3
EOF
}

confirm() {
    local msg="$1"
    if $FORCE; then return 0; fi
    printf "%b [y/N] " "$msg"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

sedi() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

ensure_trailing_newline() {
    local f="$1"
    [[ -f "$f" && -s "$f" ]] && [[ "$(tail -c1 "$f" | wc -l)" -eq 0 ]] && printf '\n' >> "$f"
}

# Interactive multi-select with arrow keys
# Usage: selected=$(pick_dirs "label1" "label2" ...)
# Returns selected labels, one per line. "__ALL__" if "All projects" is chosen.
pick_dirs() {
    local -a labels=("All projects" "$@")
    local total=${#labels[@]}
    local cursor=0
    local -a checked
    for i in {1..$total}; do checked[$i]=0; done
    checked[1]=1

    echo -e "${BOLD}Select projects:${NC} ${DIM}↑↓ navigate  space toggle  enter confirm${NC}" > /dev/tty
    echo > /dev/tty

    for i in {1..$total}; do
        local mark=" "; (( checked[$i] )) && mark="✔"
        if (( i - 1 == cursor )); then
            echo -e "  ${CYAN}▸${NC} [${GREEN}${mark}${NC}] ${BOLD}${labels[$i]}${NC}" > /dev/tty
        else
            echo -e "    [${mark}] ${labels[$i]}" > /dev/tty
        fi
    done

    tput civis > /dev/tty 2>/dev/null

    while true; do
        local key
        read -sk1 key < /dev/tty

        case "$key" in
            $'\e')
                local k2 k3
                read -sk1 -t 0.1 k2 < /dev/tty
                read -sk1 -t 0.1 k3 < /dev/tty
                if [[ "$k2" == "[" ]]; then
                    case "$k3" in
                        A) (( cursor > 0 )) && (( cursor-- )) ;;
                        B) (( cursor < total - 1 )) && (( cursor++ )) ;;
                    esac
                fi
                ;;
            ' ')
                local idx=$(( cursor + 1 ))
                if (( idx == 1 )); then
                    if (( checked[1] )); then
                        for i in {1..$total}; do checked[$i]=0; done
                    else
                        for i in {1..$total}; do checked[$i]=1; done
                    fi
                else
                    checked[$idx]=$(( 1 - checked[$idx] ))
                    if (( ! checked[$idx] )); then
                        checked[1]=0
                    else
                        local all_on=1
                        for i in {2..$total}; do
                            (( ! checked[$i] )) && all_on=0 && break
                        done
                        (( all_on )) && checked[1]=1
                    fi
                fi
                ;;
            $'\n'|'')
                break
                ;;
        esac

        printf '\e[%dA' "$total" > /dev/tty
        for i in {1..$total}; do
            printf '\e[2K' > /dev/tty
            local mark=" "; (( checked[$i] )) && mark="✔"
            if (( i - 1 == cursor )); then
                echo -e "  ${CYAN}▸${NC} [${GREEN}${mark}${NC}] ${BOLD}${labels[$i]}${NC}" > /dev/tty
            else
                echo -e "    [${mark}] ${labels[$i]}" > /dev/tty
            fi
        done
    done

    tput cnorm > /dev/tty 2>/dev/null
    echo > /dev/tty

    if (( checked[1] )); then
        echo "__ALL__"
    else
        for i in {2..$total}; do
            (( checked[$i] )) && echo "${labels[$i]}"
        done
    fi
}

# ============================= Detection ======================================

detect_pm() {
    local dir="$1"
    if [[ -f "$dir/pnpm-lock.yaml" ]]; then echo "pnpm"
    elif [[ -f "$dir/bun.lock" || -f "$dir/bun.lockb" ]]; then echo "bun"
    elif [[ -f "$dir/yarn.lock" ]]; then echo "yarn"
    elif [[ -f "$dir/package-lock.json" ]]; then echo "npm"
    else echo "unknown"
    fi
}

get_lock_glob() {
    local pm="$1"
    case "$pm" in
        npm)  echo "{package.json,package-lock.json}" ;;
        bun)  echo "{package.json,bun.lock}" ;;
        pnpm) echo "{package.json,pnpm-lock.yaml}" ;;
        yarn) echo "{package.json,yarn.lock}" ;;
    esac
}

# ============================= Layer 1: Checks ================================

check_global_npmrc() {
    local npmrc="$HOME/.npmrc"
    echo -e "  ${BOLD}~/.npmrc${NC}"
    if [[ ! -f "$npmrc" ]]; then
        echo -e "    ${RED}✘ file does not exist${NC}"
        return 1
    fi
    local ok=true
    if grep -q '^min-release-age=' "$npmrc" 2>/dev/null; then
        local val=$(grep '^min-release-age=' "$npmrc" | head -1 | cut -d= -f2)
        echo -e "    min-release-age:     ${GREEN}✔ ${val} days${NC}"
    else
        echo -e "    min-release-age:     ${RED}✘ not set${NC}"; ok=false
    fi
    if grep -q '^minimum-release-age=' "$npmrc" 2>/dev/null; then
        local val=$(grep '^minimum-release-age=' "$npmrc" | head -1 | cut -d= -f2)
        echo -e "    minimum-release-age: ${GREEN}✔ ${val} min ($(( val / 1440 ))d)${NC}"
    else
        echo -e "    minimum-release-age: ${RED}✘ not set${NC}"; ok=false
    fi
    if grep -q '^save-exact=true' "$npmrc" 2>/dev/null; then
        echo -e "    save-exact:          ${GREEN}✔ true${NC}"
    else
        echo -e "    save-exact:          ${RED}✘ not set${NC}"; ok=false
    fi
    $ok
}

check_global_bunfig() {
    local bunfig="$HOME/.bunfig.toml"
    echo -e "  ${BOLD}~/.bunfig.toml${NC}"
    if [[ ! -f "$bunfig" ]]; then
        echo -e "    ${RED}✘ file does not exist${NC}"
        return 1
    fi
    if grep -q 'minimumReleaseAge' "$bunfig" 2>/dev/null; then
        local val=$(grep 'minimumReleaseAge' "$bunfig" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
        echo -e "    minimumReleaseAge:   ${GREEN}✔ ${val}s ($(( val / 86400 ))d)${NC}"
        return 0
    else
        echo -e "    minimumReleaseAge:   ${RED}✘ not set${NC}"
        return 1
    fi
}

check_release_age() {
    local dir="$1" pm="$2"
    case "$pm" in
        npm)
            if [[ -f "$dir/.npmrc" ]] && grep -q '^min-release-age=' "$dir/.npmrc" 2>/dev/null; then
                local val=$(grep '^min-release-age=' "$dir/.npmrc" | head -1 | cut -d= -f2)
                echo "configured:${val}d"; return 0
            fi ;;
        bun)
            if [[ -f "$dir/bunfig.toml" ]] && grep -q 'minimumReleaseAge' "$dir/bunfig.toml" 2>/dev/null; then
                local val=$(grep 'minimumReleaseAge' "$dir/bunfig.toml" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
                echo "configured:$(( val / 86400 ))d"; return 0
            fi ;;
        pnpm)
            if [[ -f "$dir/pnpm-workspace.yaml" ]] && grep -q 'minimumReleaseAge' "$dir/pnpm-workspace.yaml" 2>/dev/null; then
                local val=$(grep 'minimumReleaseAge' "$dir/pnpm-workspace.yaml" | head -1 | sed 's/.*:\s*//')
                echo "configured:$(( val / 1440 ))d"; return 0
            elif [[ -f "$dir/.npmrc" ]] && grep -q '^minimum-release-age=' "$dir/.npmrc" 2>/dev/null; then
                local val=$(grep '^minimum-release-age=' "$dir/.npmrc" | head -1 | cut -d= -f2)
                echo "configured:$(( val / 1440 ))d"; return 0
            fi ;;
        yarn)
            if [[ -f "$dir/.yarnrc.yml" ]] && grep -q 'npmMinimalAgeGate' "$dir/.yarnrc.yml" 2>/dev/null; then
                local val=$(grep 'npmMinimalAgeGate' "$dir/.yarnrc.yml" | head -1 | sed "s/.*:\s*//" | tr -d "\"'")
                echo "configured:${val}"; return 0
            fi ;;
    esac
    echo "not_configured"; return 1
}

check_pinned() {
    local dir="$1" pkg="$dir/package.json"
    [[ -f "$pkg" ]] || { echo "no_pkg"; return; }
    local n=$(grep -cE '"[\^~][0-9]' "$pkg" 2>/dev/null)
    if (( n > 0 )); then echo "unpinned:$n"
    else echo "pinned"
    fi
}

check_lockfile() {
    local dir="$1" pm="$2" lockfile=""
    case "$pm" in
        npm)  lockfile="package-lock.json" ;;
        bun)  [[ -f "$dir/bun.lock" ]] && lockfile="bun.lock" || lockfile="bun.lockb" ;;
        pnpm) lockfile="pnpm-lock.yaml" ;;
        yarn) lockfile="yarn.lock" ;;
    esac
    [[ -f "$dir/$lockfile" ]] || { echo "no_lockfile"; return; }
    if git -C "$dir" rev-parse --git-dir &>/dev/null; then
        if git -C "$dir" ls-files --error-unmatch "$lockfile" &>/dev/null; then
            echo "committed"
        else
            echo "not_committed"
        fi
    else
        echo "no_git"
    fi
}

# ============================= Layer 1: Apply =================================

apply_global_npmrc() {
    local age_days="$1" age_minutes=$(( $1 * 1440 ))
    local npmrc="$HOME/.npmrc"
    local additions=()

    grep -q '^min-release-age=' "$npmrc" 2>/dev/null    || additions+=("min-release-age=$age_days")
    grep -q '^minimum-release-age=' "$npmrc" 2>/dev/null || additions+=("minimum-release-age=$age_minutes")
    grep -q '^save-exact=true' "$npmrc" 2>/dev/null      || additions+=("save-exact=true")

    if (( ${#additions[@]} == 0 )); then
        echo -e "  ${GREEN}[✔] ~/.npmrc already configured${NC}"
        return 0
    fi

    local preview=$(printf '    %s\n' "${additions[@]}")
    if confirm "  Add to ${BOLD}~/.npmrc${NC}:\n$preview"; then
        if ! $DRY_RUN; then
            [[ -f "$npmrc" ]] && ensure_trailing_newline "$npmrc"
            printf '%s\n' "${additions[@]}" >> "$npmrc"
        fi
        echo -e "  ${GREEN}[✔] Updated ~/.npmrc${NC}"
        (( applied_count++ ))
    else
        echo -e "  ${YELLOW}[—] Skipped ~/.npmrc${NC}"
        (( skipped_count++ ))
    fi
}

apply_global_bunfig() {
    local age_seconds=$(( $1 * 86400 ))
    local bunfig="$HOME/.bunfig.toml"

    if grep -q 'minimumReleaseAge' "$bunfig" 2>/dev/null; then
        echo -e "  ${GREEN}[✔] ~/.bunfig.toml already configured${NC}"
        return 0
    fi

    if confirm "  Add to ${BOLD}~/.bunfig.toml${NC}:\n    [install]\n    minimumReleaseAge = $age_seconds"; then
        if ! $DRY_RUN; then
            if [[ -f "$bunfig" ]]; then
                if grep -q '^\[install\]' "$bunfig"; then
                    sedi '/^\[install\]/a\
minimumReleaseAge = '"$age_seconds" "$bunfig"
                else
                    ensure_trailing_newline "$bunfig"
                    printf '\n[install]\nminimumReleaseAge = %d\n' "$age_seconds" >> "$bunfig"
                fi
            else
                printf '[install]\nminimumReleaseAge = %d\n' "$age_seconds" > "$bunfig"
            fi
        fi
        echo -e "  ${GREEN}[✔] Updated ~/.bunfig.toml${NC}"
        (( applied_count++ ))
    else
        echo -e "  ${YELLOW}[—] Skipped ~/.bunfig.toml${NC}"
        (( skipped_count++ ))
    fi
}

apply_release_age() {
    local dir="$1" pm="$2" age_days="$3"
    local age_minutes=$(( age_days * 1440 )) age_seconds=$(( age_days * 86400 ))

    if $DRY_RUN; then
        case "$pm" in
            npm)  echo -e "    ${DIM}would add min-release-age=$age_days to .npmrc${NC}" ;;
            bun)  echo -e "    ${DIM}would add minimumReleaseAge=$age_seconds to bunfig.toml${NC}" ;;
            pnpm) echo -e "    ${DIM}would add minimumReleaseAge: $age_minutes to config${NC}" ;;
            yarn) echo -e "    ${DIM}would add npmMinimalAgeGate: $age_minutes to .yarnrc.yml${NC}" ;;
        esac
        return 0
    fi

    case "$pm" in
        npm)
            [[ -f "$dir/.npmrc" ]] && ensure_trailing_newline "$dir/.npmrc"
            printf 'min-release-age=%d\n' "$age_days" >> "$dir/.npmrc"
            ;;
        bun)
            if [[ -f "$dir/bunfig.toml" ]] && grep -q '^\[install\]' "$dir/bunfig.toml"; then
                sedi '/^\[install\]/a\
minimumReleaseAge = '"$age_seconds" "$dir/bunfig.toml"
            elif [[ -f "$dir/bunfig.toml" ]]; then
                ensure_trailing_newline "$dir/bunfig.toml"
                printf '\n[install]\nminimumReleaseAge = %d\n' "$age_seconds" >> "$dir/bunfig.toml"
            else
                printf '[install]\nminimumReleaseAge = %d\n' "$age_seconds" > "$dir/bunfig.toml"
            fi
            ;;
        pnpm)
            if [[ -f "$dir/pnpm-workspace.yaml" ]]; then
                ensure_trailing_newline "$dir/pnpm-workspace.yaml"
                printf 'minimumReleaseAge: %d\n' "$age_minutes" >> "$dir/pnpm-workspace.yaml"
            else
                [[ -f "$dir/.npmrc" ]] && ensure_trailing_newline "$dir/.npmrc"
                printf 'minimum-release-age=%d\n' "$age_minutes" >> "$dir/.npmrc"
            fi
            ;;
        yarn)
            if [[ -f "$dir/.yarnrc.yml" ]]; then
                ensure_trailing_newline "$dir/.yarnrc.yml"
            fi
            printf 'npmMinimalAgeGate: %d\n' "$age_minutes" >> "$dir/.yarnrc.yml"
            ;;
    esac
}

apply_pin() {
    local dir="$1" pkg="$dir/package.json"
    [[ -f "$pkg" ]] || return 1
    if $DRY_RUN; then
        echo -e "    ${DIM}would strip ^ and ~ from versions in package.json${NC}"
        return 0
    fi
    sedi -E 's/"[\^~]([0-9])/"\1/g' "$pkg"
}

# ============================= Layer 2 ========================================

check_lefthook() {
    local dir="$1"
    if [[ -f "$dir/lefthook.yml" ]] && grep -q 'audit' "$dir/lefthook.yml" 2>/dev/null; then
        echo "configured"
    elif [[ -f "$dir/lefthook.yml" ]]; then
        echo "no_audit_hook"
    else
        echo "not_configured"
    fi
}

apply_lefthook() {
    local dir="$1" pm="$2"
    local lock_glob=$(get_lock_glob "$pm")

    local audit_cmd audit_full_cmd
    case "$pm" in
        npm)  audit_cmd="npm audit --audit-level=high --omit=dev";  audit_full_cmd="npm audit --audit-level=moderate" ;;
        bun)  audit_cmd="bun audit --audit-level=high --prod";      audit_full_cmd="bun audit --audit-level=moderate" ;;
        pnpm) audit_cmd="pnpm audit --audit-level=high --prod";     audit_full_cmd="pnpm audit --audit-level=moderate" ;;
        yarn) audit_cmd="yarn npm audit --severity high --environment production"; audit_full_cmd="yarn npm audit --severity moderate" ;;
        *)    return 1 ;;
    esac

    if $DRY_RUN; then
        echo -e "    ${DIM}would create lefthook.yml and install lefthook${NC}"
        return 0
    fi

    cat > "$dir/lefthook.yml" <<LEFTHOOK
pre-commit:
  parallel: true
  commands:
    audit:
      glob: "${lock_glob}"
      run: ${audit_cmd}

pre-push:
  commands:
    audit-full:
      run: ${audit_full_cmd}
LEFTHOOK

    (cd "$dir" && {
        case "$pm" in
            npm)  npm install --save-dev lefthook 2>/dev/null ;;
            bun)  bun add -d lefthook 2>/dev/null ;;
            pnpm) pnpm add -D lefthook 2>/dev/null ;;
            yarn) yarn add -D lefthook 2>/dev/null ;;
        esac
        if command -v lefthook &>/dev/null; then
            lefthook install 2>/dev/null
        elif [[ -x "node_modules/.bin/lefthook" ]]; then
            ./node_modules/.bin/lefthook install 2>/dev/null
        fi
    })
}

# ============================= Layer 3 ========================================

check_scheduled() {
    local os="$1"
    case "$os" in
        macos)
            [[ -f "$HOME/Library/LaunchAgents/com.awesome-scripts.node-audit.plist" ]] && echo "configured" || echo "not_configured" ;;
        linux)
            if systemctl --user is-enabled node-audit.timer &>/dev/null; then echo "configured"
            elif crontab -l 2>/dev/null | grep -q 'node-audit-all'; then echo "configured"
            else echo "not_configured"
            fi ;;
        *) echo "unsupported" ;;
    esac
}

apply_scheduled() {
    local os="$1" target_dir="$2"

    mkdir -p "$HOME/.local/bin" "$HOME/.local/log"
    local wrapper="$HOME/.local/bin/node-audit-all"

    if $DRY_RUN; then
        echo -e "    ${DIM}would create $wrapper${NC}"
        echo -e "    ${DIM}would set up scheduled task${NC}"
        return 0
    fi

    cat > "$wrapper" <<'AUDIT_WRAPPER'
#!/bin/zsh
SCAN_DIR="${1:-$HOME/Projects}"
VULN_PROJECTS=()

for dir in "$SCAN_DIR"/*/; do
    [[ -f "$dir/package.json" ]] || continue
    if [[ -f "$dir/pnpm-lock.yaml" ]]; then
        (cd "$dir" && pnpm audit --audit-level=high --prod &>/dev/null) || VULN_PROJECTS+=("$(basename "$dir")")
    elif [[ -f "$dir/bun.lock" || -f "$dir/bun.lockb" ]]; then
        (cd "$dir" && bun audit --audit-level=high --prod &>/dev/null) || VULN_PROJECTS+=("$(basename "$dir")")
    elif [[ -f "$dir/yarn.lock" ]]; then
        (cd "$dir" && yarn npm audit --severity high --environment production &>/dev/null) || VULN_PROJECTS+=("$(basename "$dir")")
    elif [[ -f "$dir/package-lock.json" ]]; then
        (cd "$dir" && npm audit --audit-level=high --omit=dev &>/dev/null) || VULN_PROJECTS+=("$(basename "$dir")")
    fi
done

if (( ${#VULN_PROJECTS[@]} > 0 )); then
    msg="${#VULN_PROJECTS[@]} project(s) with vulnerabilities: ${VULN_PROJECTS[*]}"
    case "$(uname -s)" in
        Darwin) osascript -e "display notification \"$msg\" with title \"Node Security Audit\" sound name \"Basso\"" ;;
        Linux)  command -v notify-send &>/dev/null && notify-send -u critical "Node Security Audit" "$msg" ;;
    esac
    echo "[$(date)] WARN: $msg"
    exit 1
else
    msg="All projects clean."
    case "$(uname -s)" in
        Darwin) osascript -e "display notification \"$msg\" with title \"Node Security Audit\"" ;;
        Linux)  command -v notify-send &>/dev/null && notify-send "Node Security Audit" "$msg" ;;
    esac
    echo "[$(date)] OK: $msg"
fi
AUDIT_WRAPPER
    chmod +x "$wrapper"
    echo -e "  ${GREEN}[✔] Created $wrapper${NC}"

    case "$os" in
        macos)
            local plist="$HOME/Library/LaunchAgents/com.awesome-scripts.node-audit.plist"
            mkdir -p "$HOME/Library/LaunchAgents"
            cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.awesome-scripts.node-audit</string>
    <key>ProgramArguments</key>
    <array>
        <string>${wrapper}</string>
        <string>${target_dir}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/.local/log/node-audit.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.local/log/node-audit.log</string>
</dict>
</plist>
PLIST
            launchctl load "$plist" 2>/dev/null
            echo -e "  ${GREEN}[✔] Loaded launchd plist (daily 09:00)${NC}"
            ;;
        linux)
            local svc_dir="$HOME/.config/systemd/user"
            mkdir -p "$svc_dir"
            cat > "$svc_dir/node-audit.service" <<SERVICE
[Unit]
Description=Node.js security audit scan

[Service]
Type=oneshot
ExecStart=${wrapper} ${target_dir}
SERVICE
            cat > "$svc_dir/node-audit.timer" <<TIMER
[Unit]
Description=Daily Node.js security audit

[Timer]
OnCalendar=*-*-* 09:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER
            systemctl --user daemon-reload
            systemctl --user enable --now node-audit.timer 2>/dev/null
            echo -e "  ${GREEN}[✔] Enabled systemd timer (daily 09:00)${NC}"
            ;;
    esac
}

# ============================= Audit ==========================================

run_audit() {
    local dir="$1" pm="$2"
    echo -e "  ${DIM}Running $pm audit...${NC}"
    local output exit_code
    output=$(cd "$dir" && {
        case "$pm" in
            npm)  npm audit --audit-level=moderate 2>&1 ;;
            bun)  bun audit --audit-level=moderate 2>&1 ;;
            pnpm) pnpm audit --audit-level=moderate 2>&1 ;;
            yarn) yarn npm audit --severity moderate 2>&1 ;;
        esac
    })
    exit_code=$?
    if (( exit_code == 0 )); then
        echo -e "    ${GREEN}✔ No vulnerabilities found${NC}"
        (( audit_clean++ ))
    else
        echo -e "    ${RED}✘ Vulnerabilities detected:${NC}"
        echo "$output" | head -20 | sed 's/^/    /'
        (( audit_vuln++ ))
    fi
}

# ============================= Parse args =====================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --layer1)       LAYER1=true ;;
        --layer2)       LAYER2=true ;;
        --layer3)       LAYER3=true ;;
        -a|--all)       LAYER1=true; LAYER2=true; LAYER3=true ;;
        --age)          AGE_DAYS="$2"; shift ;;
        --audit)        RUN_AUDIT=true ;;
        --check-only)   CHECK_ONLY=true ;;
        -n|--dry-run)   DRY_RUN=true ;;
        -f|--force)     FORCE=true ;;
        -d|--dir)       TARGET_DIR="$2"; shift ;;
        -e|--exclude)   EXCLUDE_DIRS+=("$2"); shift ;;
        --max-depth)    MAX_DEPTH="$2"; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
    shift
done

# Default: if nothing selected, show check-only report of all layers
if ! $LAYER1 && ! $LAYER2 && ! $LAYER3 && ! $RUN_AUDIT; then
    CHECK_ONLY=true
    LAYER1=true; LAYER2=true; LAYER3=true
fi

# ============================= Validate =======================================

if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}Error: directory not found: ${TARGET_DIR}${NC}"
    exit 1
fi

TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
OS=$(detect_os)

# ============================= Scan ===========================================

echo -e "${CYAN}${BOLD}Scanning${NC} ${TARGET_DIR} ...\n"

AUTO_EXCLUDE=(.next .nuxt .output .svelte-kit .turbo .vercel .cache dist build coverage)

find_args=("$TARGET_DIR")
[[ -n "$MAX_DEPTH" ]] && find_args+=(-maxdepth "$MAX_DEPTH")
for ex in "${EXCLUDE_DIRS[@]}" "${AUTO_EXCLUDE[@]}"; do
    find_args+=(-name "$ex" -prune -o)
done
find_args+=(-name "node_modules" -prune -o -name ".git" -prune -o -name "package.json" -print)

while IFS= read -r pjson; do
    if grep -qE '"(dependencies|devDependencies|scripts)"' "$pjson" 2>/dev/null; then
        PROJECT_LIST+=("$(dirname "$pjson")")
    fi
done < <(find "${find_args[@]}" 2>/dev/null | sort)

projects_found=${#PROJECT_LIST[@]}

if (( projects_found == 0 )); then
    echo -e "${YELLOW}No Node.js projects found.${NC}"
    exit 0
fi

echo -e "${BOLD}Found ${projects_found} project(s)${NC}\n"

# ============================= Interactive selection ===========================

if [[ -t 0 ]] && ! $FORCE; then
    # extract unique top-level directory names
    typeset -aU top_level_dirs
    for dir in "${PROJECT_LIST[@]}"; do
        rel="${dir#$TARGET_DIR/}"
        top="${rel%%/*}"
        [[ "$top" == "$rel" ]] && top="$(basename "$dir")"
        top_level_dirs+=("$top")
    done

    if (( ${#top_level_dirs[@]} > 1 )); then
        # count projects per top-level dir for display
        local -a dir_labels
        for tld in "${top_level_dirs[@]}"; do
            local cnt=0
            for dir in "${PROJECT_LIST[@]}"; do
                rel="${dir#$TARGET_DIR/}"
                top="${rel%%/*}"
                [[ "$top" == "$rel" ]] && top="$(basename "$dir")"
                [[ "$top" == "$tld" ]] && (( cnt++ ))
            done
            if (( cnt == 1 )); then
                dir_labels+=("${tld} ${DIM}(1 project)${NC}")
            else
                dir_labels+=("${tld} ${DIM}(${cnt} projects)${NC}")
            fi
        done

        selection=$(pick_dirs "${dir_labels[@]}")

        if [[ -z "$selection" ]]; then
            echo -e "${YELLOW}No projects selected.${NC}"
            exit 0
        fi

        if [[ "$selection" != "__ALL__" ]]; then
            # filter PROJECT_LIST to only selected top-level dirs
            local -a filtered
            while IFS= read -r sel_label; do
                sel_name="${sel_label%% *}"
                for dir in "${PROJECT_LIST[@]}"; do
                    rel="${dir#$TARGET_DIR/}"
                    top="${rel%%/*}"
                    [[ "$top" == "$rel" ]] && top="$(basename "$dir")"
                    [[ "$top" == "$sel_name" ]] && filtered+=("$dir")
                done
            done <<< "$selection"
            PROJECT_LIST=("${filtered[@]}")
            projects_found=${#PROJECT_LIST[@]}
            echo -e "${DIM}Selected ${projects_found} project(s)${NC}\n"
        fi
    fi
fi

# ============================= Report =========================================

# --- Global config (Layer 1) ---
if $LAYER1; then
    echo -e "${BOLD}${CYAN}Global Configuration${NC}\n"
    check_global_npmrc
    echo
    check_global_bunfig
    echo
fi

# --- Per-project ---
echo -e "${BOLD}${CYAN}Projects${NC}\n"

l1_configured=0 l1_missing=0
pin_ok=0 pin_bad=0

for i in {1..${#PROJECT_LIST[@]}}; do
    dir="${PROJECT_LIST[$i]}"
    pm=$(detect_pm "$dir")
    PROJECT_PM_LIST+=("$pm")
    name=$(basename "$dir")
    rel="${dir/#$HOME/~}"

    echo -e "  ${BOLD}${name}${NC} ${DIM}${rel}${NC}"

    if [[ "$pm" == "unknown" ]]; then
        echo -e "    ${YELLOW}⚠ no lock file — package manager unknown${NC}\n"
        continue
    fi
    echo -e "    ${DIM}pm:${NC} ${CYAN}${pm}${NC}"

    if $LAYER1; then
        age_status=$(check_release_age "$dir" "$pm")
        if [[ "$age_status" == configured:* ]]; then
            echo -e "    ${DIM}release age:${NC}  ${GREEN}✔ ${age_status#configured:}${NC}"
            (( l1_configured++ ))
        else
            echo -e "    ${DIM}release age:${NC}  ${RED}✘ not configured${NC}"
            NEED_RELEASE_AGE+=("$i")
            (( l1_missing++ ))
        fi

        pin_status=$(check_pinned "$dir")
        if [[ "$pin_status" == "pinned" ]]; then
            echo -e "    ${DIM}pinned deps:${NC}  ${GREEN}✔ all exact${NC}"
            (( pin_ok++ ))
        elif [[ "$pin_status" == unpinned:* ]]; then
            echo -e "    ${DIM}pinned deps:${NC}  ${RED}✘ ${pin_status#unpinned:} unpinned${NC}"
            NEED_PIN+=("$i")
            (( pin_bad++ ))
        fi

        lock_status=$(check_lockfile "$dir" "$pm")
        case "$lock_status" in
            committed)     echo -e "    ${DIM}lockfile:${NC}     ${GREEN}✔ committed${NC}" ;;
            not_committed) echo -e "    ${DIM}lockfile:${NC}     ${RED}✘ not committed${NC}" ;;
            no_lockfile)   echo -e "    ${DIM}lockfile:${NC}     ${YELLOW}⚠ not found${NC}" ;;
            no_git)        echo -e "    ${DIM}lockfile:${NC}     ${DIM}— not a git repo${NC}" ;;
        esac
    fi

    if $LAYER2; then
        lh=$(check_lefthook "$dir")
        case "$lh" in
            configured)     echo -e "    ${DIM}lefthook:${NC}     ${GREEN}✔ audit hooks active${NC}" ;;
            no_audit_hook)  echo -e "    ${DIM}lefthook:${NC}     ${YELLOW}⚠ exists but no audit hook${NC}"; NEED_LEFTHOOK+=("$i") ;;
            not_configured) echo -e "    ${DIM}lefthook:${NC}     ${RED}✘ not configured${NC}"; NEED_LEFTHOOK+=("$i") ;;
        esac
    fi

    echo
done

# --- Scheduled scan (Layer 3) ---
if $LAYER3; then
    echo -e "${BOLD}${CYAN}Scheduled Scan${NC}"
    sched=$(check_scheduled "$OS")
    case "$sched" in
        configured)     echo -e "  ${GREEN}✔ Daily audit scan is active${NC}" ;;
        not_configured) echo -e "  ${RED}✘ No scheduled scan configured${NC}" ;;
        unsupported)    echo -e "  ${YELLOW}⚠ Unsupported OS for scheduled scans${NC}" ;;
    esac
    echo
fi

# --- Summary ---
echo -e "${BOLD}${CYAN}Summary${NC}"
echo -e "  Projects:    ${BOLD}$projects_found${NC}"
if $LAYER1; then
    echo -e "  Release age: ${GREEN}$l1_configured ok${NC}  ${RED}$l1_missing missing${NC}"
    echo -e "  Pinned deps: ${GREEN}$pin_ok ok${NC}  ${RED}$pin_bad unpinned${NC}"
fi
echo

# ============================= Check-only gate ================================

if $CHECK_ONLY; then
    echo -e "${YELLOW}Check-only mode — no changes made.${NC}"
    exit 0
fi

# ============================= Apply ==========================================

echo -e "${BOLD}${CYAN}Applying changes${NC}\n"

# --- Layer 1: Global ---
if $LAYER1; then
    apply_global_npmrc "$AGE_DAYS"
    apply_global_bunfig "$AGE_DAYS"
    echo
fi

# --- Layer 1: Per-project release age ---
if $LAYER1 && (( ${#NEED_RELEASE_AGE[@]} > 0 )); then
    for idx in "${NEED_RELEASE_AGE[@]}"; do
        dir="${PROJECT_LIST[$idx]}"
        pm="${PROJECT_PM_LIST[$idx]}"
        name=$(basename "$dir")
        if confirm "  ${BOLD}$name${NC} [$pm]: Add release age (${AGE_DAYS}d)?"; then
            apply_release_age "$dir" "$pm" "$AGE_DAYS"
            echo -e "    ${GREEN}[✔] Release age configured${NC}"
            (( applied_count++ ))
        else
            echo -e "    ${YELLOW}[—] Skipped${NC}"
            (( skipped_count++ ))
        fi
    done
    echo
fi

# --- Layer 1: Pin deps ---
if $LAYER1 && (( ${#NEED_PIN[@]} > 0 )); then
    for idx in "${NEED_PIN[@]}"; do
        dir="${PROJECT_LIST[$idx]}"
        name=$(basename "$dir")
        n=$(check_pinned "$dir"); n="${n#unpinned:}"
        if confirm "  ${BOLD}$name${NC}: Pin $n deps (strip ^ and ~)?"; then
            apply_pin "$dir"
            echo -e "    ${GREEN}[✔] Dependencies pinned${NC}"
            (( applied_count++ ))
        else
            echo -e "    ${YELLOW}[—] Skipped${NC}"
            (( skipped_count++ ))
        fi
    done
    echo
fi

# --- Layer 2: Lefthook ---
if $LAYER2 && (( ${#NEED_LEFTHOOK[@]} > 0 )); then
    for idx in "${NEED_LEFTHOOK[@]}"; do
        dir="${PROJECT_LIST[$idx]}"
        pm="${PROJECT_PM_LIST[$idx]}"
        name=$(basename "$dir")
        if confirm "  ${BOLD}$name${NC} [$pm]: Install lefthook with audit hooks?"; then
            apply_lefthook "$dir" "$pm"
            echo -e "    ${GREEN}[✔] Lefthook configured${NC}"
            (( applied_count++ ))
        else
            echo -e "    ${YELLOW}[—] Skipped${NC}"
            (( skipped_count++ ))
        fi
    done
    echo
fi

# --- Layer 3: Scheduled scan ---
if $LAYER3; then
    sched=$(check_scheduled "$OS")
    if [[ "$sched" == "not_configured" ]]; then
        if confirm "  Set up daily audit scan (09:00)?"; then
            apply_scheduled "$OS" "$TARGET_DIR"
            (( applied_count++ ))
        else
            echo -e "  ${YELLOW}[—] Skipped${NC}"
            (( skipped_count++ ))
        fi
        echo
    fi
fi

# ============================= Audit ==========================================

if $RUN_AUDIT; then
    echo -e "${BOLD}${CYAN}Security Audit${NC}\n"
    for i in {1..${#PROJECT_LIST[@]}}; do
        dir="${PROJECT_LIST[$i]}"
        pm="${PROJECT_PM_LIST[$i]}"
        [[ "$pm" == "unknown" ]] && continue
        echo -e "  ${BOLD}$(basename "$dir")${NC} ${DIM}[$pm]${NC}"
        run_audit "$dir" "$pm"
        echo
    done
fi

# ============================= Final summary ==================================

echo -e "${BOLD}Done.${NC}"
if (( applied_count > 0 )); then
    echo -e "  Applied: ${GREEN}${applied_count}${NC} changes"
fi
if (( skipped_count > 0 )); then
    echo -e "  Skipped: ${YELLOW}${skipped_count}${NC} changes"
fi
if $RUN_AUDIT; then
    echo -e "  Audit:   ${GREEN}${audit_clean} clean${NC}  ${RED}${audit_vuln} vulnerable${NC}"
fi
if $DRY_RUN; then
    echo -e "\n  ${YELLOW}Dry-run mode — no actual changes were made.${NC}"
fi
