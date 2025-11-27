#!/bin/zsh

# ==============================================================================
# Script Name: clean_zsh.sh
# Description: Wipes Zsh history and sessions, restoring only preferred commands.
# ==============================================================================

# --- Configuration ---
HISTORY_FILE="${HOME}/.zsh_history"
SESSIONS_DIR="${HOME}/.zsh_sessions"
PREFERRED_FILE="${HOME}/.zsh_preferred_commands"

# Colors for output 
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Zsh cleanup process...${NC}"

# 1. Remove .zsh_history
if [[ -f "$HISTORY_FILE" ]]; then
    rm "$HISTORY_FILE"
    echo -e "${GREEN}[✔] Deleted ${HISTORY_FILE}${NC}"
else
    echo -e "${YELLOW}[-] No history file found at ${HISTORY_FILE}${NC}"
fi

# 2. Remove .zsh_sessions folder
if [[ -d "$SESSIONS_DIR" ]]; then
    rm -rf "$SESSIONS_DIR"
    echo -e "${GREEN}[✔] Deleted ${SESSIONS_DIR} directory${NC}"
else
    echo -e "${YELLOW}[-] No sessions directory found at ${SESSIONS_DIR}${NC}"
fi

# 3. Restore Preferred Commands or Create Empty File
if [[ -f "$PREFERRED_FILE" ]]; then
    cp "$PREFERRED_FILE" "$HISTORY_FILE"
    echo -e "${GREEN}[✔] Restored preferred commands to ${HISTORY_FILE}${NC}"
else
    # Create an empty file to prevent "no such file" errors on next login
    touch "$HISTORY_FILE"
    echo -e "${YELLOW}[!] No preferred commands file found (${PREFERRED_FILE}). Created empty history.${NC}"
fi

# 4. Fix Permissions (Security Best Practice)
chmod 600 "$HISTORY_FILE"
echo -e "${GREEN}[✔] Set strict permissions (600) on .zsh_history${NC}"

# 5. Apply Changes to Current Shell
# Check if the script is being sourced (run within current shell) or executed (subshell)
if [[ "$ZSH_EVAL_CONTEXT" == "toplevel" ]]; then
    echo -e "\n${YELLOW}[!] NOTICE: You ran this as an executable.${NC}"
    echo "The file is clean, but this specific window still holds old history in memory."
    echo "To fix this window immediately, run:"
    echo -e "  ${RED}HISTSIZE=0; HISTSIZE=50000; fc -R${NC}"
    echo ""
    echo "Tip: Next time, run as ${GREEN}source clean_zsh.sh${NC} to apply automatically."
else
    # Script is being sourced, so we can directly modify the current shell's memory
    # 1. Clear in-memory history by temporarily setting HISTSIZE to 0
    local old_histsize=$HISTSIZE
    HISTSIZE=0
    # 2. Restore HISTSIZE (defaulting to 50000 if it was 0 or unset, though we just set it to 0)
    # If old_histsize was 0, we probably want a useful default.
    if [[ "$old_histsize" -eq 0 ]]; then
        HISTSIZE=50000
    else
        HISTSIZE=$old_histsize
    fi
    # 3. Read the (now empty/preferred) history file back into memory
    fc -R
    echo -e "${GREEN}[✔] Automatically reloaded history for this session!${NC}"
fi