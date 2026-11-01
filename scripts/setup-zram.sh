#!/usr/bin/env bash
# Initialize ZRAM block device (8GB zstd) with priority 100
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root." >&2
    exit 1
fi

echo "[+] Setting up ZRAM swap tier..."

# 1. Load module
modprobe zram num_devices=1 2>/dev/null || true

# 2. Check if /dev/zram0 is already active
if ! swapon --show | grep -q "/dev/zram0"; then
    zramctl /dev/zram0 --size 8G --algorithm zstd 2>/dev/null || zramctl --find --size 8G --algorithm zstd 2>/dev/null
    mkswap /dev/zram0 >/dev/null 2>&1
    swapon -p 100 /dev/zram0
    echo "[+] /dev/zram0 activated (8GB, zstd, Priority 100)."
else
    echo "[+] /dev/zram0 is already active."
fi

# 3. Demote disk swap file priority to 5 (fallback only)
for swap_device in $(swapon --show=NAME --noheadings); do
    if [ "$swap_device" != "/dev/zram0" ]; then
        current_prio=$(swapon --show=PRIO,NAME --noheadings | grep "$swap_device" | awk '{print $1}')
        if [ "$current_prio" != "5" ]; then
            echo "[+] Demoting $swap_device to fallback priority 5..."
            swapoff "$swap_device" 2>/dev/null || true
            swapon -p 5 "$swap_device" 2>/dev/null || true
        fi
    fi
done

echo "[+] ZRAM memory tiering configured successfully."
