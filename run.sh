#!/usr/bin/env bash

# This script is a universal runner for scripts in the awesome-scripts repository.
# It automatically detects the script type (JavaScript, Python, Shell) and runs it
# with the appropriate engine (bun/node, python3/python, bash).

if [ -z "$1" ]; then
    echo "Usage: ./run.sh <script_name>"
    echo "Example: ./run.sh crossover_trial_reset"
    exit 1
fi

SCRIPT_ARG="$1"
# Shift so we can pass any remaining arguments to the script being run
shift
REST_ARGS=("$@")

# Determine the directory where this script itself is located.
# This allows us to find the actual scripts (sh, python, javascript) even if
# we are running this from another path (like after installation to ~/bin/scripts).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Helper function to find the script
find_script() {
    local target="$1"
    
    # 1. Exact match in current directory
    if [ -f "$target" ]; then
        echo "$target"
        return 0
    fi
    
    # 2. Match with obvious extensions in current directory
    for ext in sh py js ts; do
        if [ -f "${target}.${ext}" ]; then
            echo "${target}.${ext}"
            return 0
        fi
    done
    
    # 3. Match in known subdirectories of SCRIPT_DIR
    for dir in sh python javascript; do
        if [ -d "$SCRIPT_DIR/$dir" ]; then
            # Exact match in subdirectory
            if [ -f "$SCRIPT_DIR/$dir/$target" ]; then
                echo "$SCRIPT_DIR/$dir/$target"
                return 0
            fi
            # Match with extensions in subdirectory
            for ext in sh py js ts; do
                if [ -f "$SCRIPT_DIR/$dir/${target}.${ext}" ]; then
                    echo "$SCRIPT_DIR/$dir/${target}.${ext}"
                    return 0
                fi
            done
        fi
    done
    
    # Return empty if not found
    echo ""
}

SCRIPT_PATH=$(find_script "$SCRIPT_ARG")

if [ -z "$SCRIPT_PATH" ]; then
    echo "Error: Script '$SCRIPT_ARG' not found in current directory or known subdirectories (sh, python, javascript)."
    exit 1
fi

EXTENSION="${SCRIPT_PATH##*.}"

# Determine runner based on extension and path
if [ "$EXTENSION" = "js" ] || [ "$EXTENSION" = "ts" ] || [[ "$SCRIPT_PATH" == *"javascript/"* ]]; then
    if command -v bun >/dev/null 2>&1; then
        bun "$SCRIPT_PATH" "${REST_ARGS[@]}"
    elif command -v node >/dev/null 2>&1; then
        node "$SCRIPT_PATH" "${REST_ARGS[@]}"
    else
        echo "Error: Neither 'bun' nor 'node' is installed."
        exit 1
    fi
elif [ "$EXTENSION" = "py" ] || [[ "$SCRIPT_PATH" == *"python/"* ]]; then
    if command -v python3 >/dev/null 2>&1; then
        python3 "$SCRIPT_PATH" "${REST_ARGS[@]}"
    elif command -v python >/dev/null 2>&1; then
        python "$SCRIPT_PATH" "${REST_ARGS[@]}"
    else
        echo "Error: 'python3' or 'python' is not installed."
        exit 1
    fi
elif [ "$EXTENSION" = "sh" ] || [[ "$SCRIPT_PATH" == *"sh/"* ]]; then
    sh "$SCRIPT_PATH" "${REST_ARGS[@]}"
else
    # Fallback: try executing it directly if it has executable permissions (and maybe a shebang)
    if [ -x "$SCRIPT_PATH" ]; then
        "$SCRIPT_PATH" "${REST_ARGS[@]}"
    else
        echo "Error: Unknown script type and file is not executable: $SCRIPT_PATH"
        exit 1
    fi
fi
