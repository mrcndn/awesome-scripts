#!/bin/bash

# delete_history.sh - Safely clear bash history

# Check if user wants to clear all history
if [ "$1" == "--all" ]; then
    echo "Clearing all bash history..."
    cat /dev/null > ~/.bash_history && history -c && exit
    echo "History cleared."
    exit 0
fi

# Check if user wants to delete specific lines (last N lines)
if [[ "$1" =~ ^[0-9]+$ ]]; then
    LINES=$1
    echo "Deleting last $LINES lines from history..."
    # This is a bit tricky in a running shell, but for the file:
    head -n -"$LINES" ~/.bash_history > ~/.bash_history.tmp && mv ~/.bash_history.tmp ~/.bash_history
    # Also clear from current session history if possible, but 'history -d' works on offsets.
    # A simpler approach for the file is usually what's wanted.
    echo "Removed last $LINES lines from ~/.bash_history"
    exit 0
fi

echo "Usage: $0 [--all | N]"
echo "  --all : Clear entire history"
echo "  N     : Remove last N lines from history file"
