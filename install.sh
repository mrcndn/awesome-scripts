#!/usr/bin/env bash

# Installation script for awesome-scripts

TARGET_DIR="$HOME/bin/scripts"

echo "Installing awesome-scripts to $TARGET_DIR..."

# 1. Create target directory
mkdir -p "$TARGET_DIR"

# 2. Copy scripts and directories
echo "Copying scripts..."
# Copy specific scripts and folders to keep the structure clean
cp -r sh python javascript "$TARGET_DIR/"
cp run.sh "$TARGET_DIR/run_script"

# 3. Make the runner script executable
chmod +x "$TARGET_DIR/run_script"

# 4. Determine shells and profiles to modify
PROFILES_UPDATED=0

# Add to PATH function
add_to_path() {
    local shell_rc="$1"
    if [ -f "$shell_rc" ]; then
        if ! grep -q "$TARGET_DIR" "$shell_rc" 2>/dev/null; then
            echo "Adding $TARGET_DIR to PATH in $shell_rc..."
            echo "" >> "$shell_rc"
            echo "# Added by awesome-scripts install script" >> "$shell_rc"
            echo "export PATH=\"\$PATH:$TARGET_DIR\"" >> "$shell_rc"
            PROFILES_UPDATED=$((PROFILES_UPDATED + 1))
        else
            printf "\n\033[32m%s is already in your PATH configuration (%s).\033[0m\n" "$TARGET_DIR" "$shell_rc"
        fi
    fi
}

# Check zsh
add_to_path "$HOME/.zshrc"

# Check bash (prefer .bash_profile over .bashrc for macOS, but check both)
if [ -f "$HOME/.bash_profile" ]; then
    add_to_path "$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
    add_to_path "$HOME/.bashrc"
fi

# Print final result
if [ "$PROFILES_UPDATED" -gt 0 ]; then
    printf "\n\033[32mInstallation complete!\033[0m\n"
    printf "Please restart your terminal or run \033[33msource ~/.zshrc\033[0m (or your respective profile) to use the 'run_script' command.\n"
else
    printf "Installation complete! You can now use the \033[33mrun_script\033[0m command.\n"
fi
