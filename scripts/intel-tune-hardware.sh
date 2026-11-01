#!/usr/bin/env bash
# Hardware tuning executor for Intel Core mobile & desktop processors
set -euo pipefail

# 1. Ensure MSR module is loaded
modprobe msr 2>/dev/null || true

# 2. Adjust Intel RAPL PL1 & PL2 limits if available
RAPL_DIR="/sys/class/powercap/intel-rapl/intel-rapl:0"
if [ -d "$RAPL_DIR" ]; then
    # Set PL1 = 25W (25,000,000 uW), PL2 = 35W (35,000,000 uW)
    [ -f "$RAPL_DIR/constraint_0_power_limit_uw" ] && echo 25000000 > "$RAPL_DIR/constraint_0_power_limit_uw" 2>/dev/null || true
    [ -f "$RAPL_DIR/constraint_1_power_limit_uw" ] && echo 35000000 > "$RAPL_DIR/constraint_1_power_limit_uw" 2>/dev/null || true
fi

# 3. Apply intel-undervolt daemon config if installed
if command -v intel-undervolt >/dev/null 2>&1; then
    intel-undervolt apply >/dev/null 2>&1 || true
fi

# 4. Configure Intel EPP (Energy Performance Preference) & Governor
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$epp" ] && echo performance > "$epp" 2>/dev/null || true
done

for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$gov" ] && echo performance > "$gov" 2>/dev/null || true
done
