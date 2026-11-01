#!/usr/bin/env bash
# Rollback script to restore factory defaults
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "[+] Starting Rollback & Uninstallation..."

# 1. Stop and disable systemd units
echo "[+] Disabling systemd persistence units..."
systemctl disable --now linux-boost.timer linux-boost.service 2>/dev/null || true
rm -f /etc/systemd/system/linux-boost.service /etc/systemd/system/linux-boost.timer
systemctl daemon-reload

# 2. Remove worker and configs
echo "[+] Removing configuration files..."
rm -f /usr/local/bin/linux-hardware-tune.sh
rm -f /etc/sysctl.d/99-performance.conf
rm -f /etc/systemd/journald.conf.d/00-limit-size.conf

# 3. Teardown ZRAM
echo "[+] Tearing down ZRAM block device..."
if swapon --show | grep -q "/dev/zram0"; then
    swapoff /dev/zram0 2>/dev/null || true
fi
zramctl --reset /dev/zram0 2>/dev/null || true
rmmod zram 2>/dev/null || true

# Restore SSD swap priority
if swapon --show | grep -q "/swap.img"; then
    swapoff /swap.img 2>/dev/null || true
    swapon -p -2 /swap.img 2>/dev/null || true
fi

# 4. Reset CPU scaling governor to default
echo "[+] Restoring scaling governors and frequency limits..."
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$gov" ] && echo powersave > "$gov" 2>/dev/null || echo schedutil > "$gov" 2>/dev/null || true
done

TARGET_USER="${SUDO_USER:-}"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    rm -f "$USER_HOME/.local/share/applications/code_code.desktop"
    echo "[+] Cleaned up user-space launcher overrides."
fi

echo "[+] Rollback complete. Reboot recommended to fully reset hardware P-States to factory."
