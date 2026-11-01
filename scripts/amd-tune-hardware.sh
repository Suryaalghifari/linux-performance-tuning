#!/usr/bin/env bash
# Hardware tuning executor for AMD Zen / Picasso mobile APUs
set -euo pipefail

# 1. Unlock MSR in kernel
if [ -f /sys/module/msr/parameters/allow_writes ]; then
    echo on > /sys/module/msr/parameters/allow_writes
fi

# 2. Overclock P-States via amdctl
# Look for amdctl in common paths
AMDCTL_BIN=""
for candidate in /home/*/.local/bin/amdctl /usr/local/bin/amdctl /usr/bin/amdctl; do
    if [ -x "$candidate" ]; then
        AMDCTL_BIN="$candidate"
        break
    fi
done

if [ -n "$AMDCTL_BIN" ]; then
    # P0 = 3300 MHz (FID=132, DID=8, VID=53 -> 1218mV)
    "$AMDCTL_BIN" -m -p 0 -f 132 >/dev/null 2>&1 || true
    # P1 = 3000 MHz (FID=120, DID=8, VID=53 -> 1218mV)
    "$AMDCTL_BIN" -m -p 1 -f 120 -d 8 -v 53 >/dev/null 2>&1 || true
fi

# 3. Lock scaling frequency and governor
for min_f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do
    [ -f "$min_f" ] && echo 2400000 > "$min_f" 2>/dev/null || true
done
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$gov" ] && echo performance > "$gov" 2>/dev/null || true
done

# 4. Enable CPU Boost
if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
    echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
fi

# 5. Apply SMU Power Limits via ryzenadj
RYZENADJ_BIN=""
for candidate in /home/*/.local/bin/ryzenadj /usr/local/bin/ryzenadj /usr/bin/ryzenadj; do
    if [ -x "$candidate" ]; then
        RYZENADJ_BIN="$candidate"
        break
    fi
done

if [ -n "$RYZENADJ_BIN" ]; then
    "$RYZENADJ_BIN" \
        --stapm-limit=20000 \
        --fast-limit=24000 \
        --slow-limit=20000 \
        --tctl-temp=90 \
        --max-performance >/dev/null 2>&1 || true
fi
