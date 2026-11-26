#!/usr/bin/env bash
# Hardware tuning executor for AMD Zen / Picasso mobile APUs
set -euo pipefail

# 1. Unlock MSR in kernel
if [ -f /sys/module/msr/parameters/allow_writes ]; then
    echo on > /sys/module/msr/parameters/allow_writes
fi

# 2. P-State dibiarkan sesuai firmware.
#    Picasso 3150U (HP Badai) hanya mengekspos 3 P-state: 2.4 / 1.7 / 1.4 GHz, cpuinfo_max = 2.4 GHz.
#    Memaksa P0 = 3.3 GHz lewat MSR hanya membuat amdctl tidak sinkron dengan acpi-cpufreq
#    (clock terbaca di bawah min, suhu idle 70 C, TDP naik tanpa clock nyata).
#    Lihat docs/09-incident-firefox-meet-crash.md.

# 3. Governor schedutil dengan minimum di P-state terendah yang tersedia.
for min_f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do
    [ -f "$min_f" ] || continue
    lowest=$(tr ' ' '\n' < "${min_f%scaling_min_freq}scaling_available_frequencies" 2>/dev/null | sort -n | head -1)
    echo "${lowest:-1400000}" > "$min_f" 2>/dev/null || true
done
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$gov" ] && echo schedutil > "$gov" 2>/dev/null || true
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
    # 15 W STAPM / 20 W FAST / 15 W SLOW (stock TDP), ceiling 85 C.
    # Nilai 20/24/20 + --max-performance membuat paket di atas TDP di heatsink sekecil ini.
    "$RYZENADJ_BIN" \
        --stapm-limit=15000 \
        --fast-limit=20000 \
        --slow-limit=15000 \
        --tctl-temp=85 >/dev/null 2>&1 || true
fi

# 6. NVMe Readahead optimization to RAM (1024 KB)
for q in /sys/block/nvme*/queue/read_ahead_kb; do
    [ -f "$q" ] && echo 1024 > "$q" 2>/dev/null || true
done
