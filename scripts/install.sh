#!/usr/bin/env bash
# Unified Performance Tuning Installer for Linux Desktops (AMD & Intel)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (use sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "[+] Starting Linux Performance Tuning Installation..."

# 1. Check prerequisites
echo "[+] Checking Security & Kernel Lockdown status..."
if [ -f /sys/kernel/security/lockdown ]; then
    LOCKDOWN=$(cat /sys/kernel/security/lockdown)
    if [[ "$LOCKDOWN" == *"[integrity]"* ]]; then
        echo "[!] WARNING: Secure Boot is enabled (lockdown is integrity)." >&2
        echo "    Hardware register tuning (MSR/SMU) will be blocked." >&2
        echo "    Please reboot, enter BIOS, disable Secure Boot, and re-run this script." >&2
    else
        echo "[+] Kernel lockdown is none (Secure Boot disabled). Hardware access OK."
    fi
fi

# Enable MSR module and writes
modprobe msr 2>/dev/null || true
if [ -f /sys/module/msr/parameters/allow_writes ]; then
    echo on > /sys/module/msr/parameters/allow_writes
    echo "[+] MSR writes unlocked in kernel."
fi

# 2. Detect CPU Vendor
CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
echo "[+] Detected CPU Vendor: $CPU_VENDOR"

# Copy worker script to system location
mkdir -p /usr/local/bin
if [ "$CPU_VENDOR" = "AuthenticAMD" ]; then
    echo "[+] Configuring AMD hardware worker..."
    cp "$SCRIPT_DIR/amd-tune-hardware.sh" /usr/local/bin/linux-hardware-tune.sh
elif [ "$CPU_VENDOR" = "GenuineIntel" ]; then
    echo "[+] Configuring Intel hardware worker..."
    cp "$SCRIPT_DIR/intel-tune-hardware.sh" /usr/local/bin/linux-hardware-tune.sh
else
    echo "[!] Unrecognized vendor. Defaulting to generic hardware worker..."
    cp "$SCRIPT_DIR/amd-tune-hardware.sh" /usr/local/bin/linux-hardware-tune.sh
fi
chmod +x /usr/local/bin/linux-hardware-tune.sh

# 3. Setup Sysctl & Journald configs
echo "[+] Deploying sysctl and journald performance configurations..."
cp "$REPO_ROOT/configs/99-performance.conf" /etc/sysctl.d/99-performance.conf
sysctl --system >/dev/null 2>&1

mkdir -p /etc/systemd/journald.conf.d
cp "$REPO_ROOT/configs/journald-size.conf" /etc/systemd/journald.conf.d/00-limit-size.conf
systemctl restart systemd-journald >/dev/null 2>&1
journalctl --vacuum-size=100M >/dev/null 2>&1 || true

# 4. Setup ZRAM
echo "[+] Initializing ZRAM and memory tiering..."
bash "$SCRIPT_DIR/setup-zram.sh"

# 5. Execute initial hardware tuning run
echo "[+] Applying initial hardware clocks and power limits..."
/usr/local/bin/linux-hardware-tune.sh || true

# 6. Install Systemd Persistence Service & Timer
echo "[+] Installing systemd persistence units..."
cp "$REPO_ROOT/systemd/linux-boost.service" /etc/systemd/system/linux-boost.service
cp "$REPO_ROOT/systemd/linux-boost.timer" /etc/systemd/system/linux-boost.timer

systemctl daemon-reload
systemctl enable --now linux-boost.timer linux-boost.service

# 7. Setup user-space app acceleration if invoked via sudo
TARGET_USER="${SUDO_USER:-}"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    echo "[+] Configuring user-space optimizations for user: $TARGET_USER..."
    sudo -u "$TARGET_USER" bash "$SCRIPT_DIR/setup-vscode-gpu.sh" || true
    sudo -u "$TARGET_USER" bash "$SCRIPT_DIR/setup-firefox-ram.sh" || true
fi

echo ""
echo "=========================================================="
echo "[+] Installation complete! System is running at max speed."
echo "    Verify hardware clocks using: sudo turbostat -i 1"
echo "=========================================================="
