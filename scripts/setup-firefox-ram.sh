#!/usr/bin/env bash
# Inject zero-disk RAM caching, multi-tab persistence, and VA-API hardware acceleration into Firefox profiles
set -euo pipefail

echo "[+] Scanning for Firefox profiles..."

FIREFOX_CONFIG="
// High RAM Multi-Tab & Zero Disk Thrashing Configuration (20GB RAM Edition)
// 1. Zero Disk Cache & Massive RAM Cache
user_pref(\"browser.cache.disk.enable\", false);
user_pref(\"browser.cache.disk.smart_size.enabled\", false);
user_pref(\"browser.cache.memory.enable\", true);
user_pref(\"browser.cache.memory.capacity\", 2097152); // 2GB memory cache in RAM per profile
user_pref(\"browser.cache.memory.max_entry_size\", 102400); // 100MB per object
user_pref(\"media.memory_cache_max_size\", 1048576); // 1GB media stream buffer

// 2. Disable Tab Sleeping (Keep 20-30 tabs alive in RAM for 0ms tab switching)
user_pref(\"browser.tabs.unloadOnLowMemory\", false);
user_pref(\"browser.sessionhistory.max_entries\", 20);
user_pref(\"browser.sessionhistory.max_total_viewers\", 20); // bfcache: keep 20 pages pre-rendered in RAM

// 3. Multi-Process Concurrency
user_pref(\"dom.ipc.processCount\", 16);

// 4. Hardware Video Acceleration (AMD Radeon Vega 3 VCN Engine)
user_pref(\"media.ffmpeg.vaapi.enabled\", true);
user_pref(\"media.hardware-video-decoding.force-enabled\", true);
user_pref(\"gfx.webrender.all\", true);
user_pref(\"widget.dmabuf.wayland.enabled\", true);
"

# Search in both native and Snap directories
PROFILE_DIRS=()
for base in "$HOME/.mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox"; do
    if [ -d "$base" ]; then
        while IFS= read -r -d '' p; do
            PROFILE_DIRS+=("$p")
        done < <(find "$base" -maxdepth 1 -mindepth 1 -type d -name "*.*" ! -name "*.zap-client-profile" -print0)
    fi
done

if [ ${#PROFILE_DIRS[@]} -eq 0 ]; then
    echo "[!] No Firefox profile directories found."
    exit 0
fi

for p in "${PROFILE_DIRS[@]}"; do
    target="$p/user.js"
    echo "$FIREFOX_CONFIG" >> "$target"
    echo "[+] Applied user.js to: $(basename "$p")"
done

echo "[+] Firefox RAM cache & VA-API configured for ${#PROFILE_DIRS[@]} profiles."
