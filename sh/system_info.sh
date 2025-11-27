#!/bin/bash

# system_info.sh - Display basic system information

echo "------------------------------------------------"
echo "System Information"
echo "------------------------------------------------"

echo "Hostname: $(hostname)"
echo "OS: $(uname -s)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Uptime: $(uptime | awk -F'( |,|:)+' '{print $6,$7",",$8,"hours,",$9,"minutes"}')"
echo "Current User: $(whoami)"
echo "Date: $(date)"

echo "------------------------------------------------"
