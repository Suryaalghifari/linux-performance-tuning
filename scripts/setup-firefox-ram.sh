#!/usr/bin/env bash
# Kelola prefs Firefox (cache, tab, proses, VA-API) secara idempoten.
# Target hardware: 16-18 GiB RAM / 2C4T (HP Badai). Bukan "20 GB RAM Edition".
#
# Perubahan vs versi lama (lihat docs/09-incident-firefox-meet-crash.md):
#   - disk cache dihidupkan lagi (256 MB) supaya objek tidak semua menumpuk di RAM
#   - memory cache 512 MB (dulu 2 GB), media cache 256 MB (dulu 1 GB)
#   - content process 8 (dulu 16 di CPU 4 thread)
#   - tab unloadOnLowMemory dibiarkan aktif (dulu dipaksa mati)
#   - widget.dmabuf.wayland.enabled & hardware-video-decoding.force-enabled dimatikan:
#     jalur ini yang bikin Firefox SIGSEGV di screencast PipeWire saat stop share screen
set -euo pipefail

BEGIN_MARK="// >>> linux-performance-tuning:firefox (managed block, jangan edit manual) >>>"
END_MARK="// <<< linux-performance-tuning:firefox <<<"

BLOCK=$(cat <<'EOF'
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 262144); // 256 MB disk cache
user_pref("browser.cache.disk.smart_size.enabled", true);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 524288); // 512 MB RAM cache
user_pref("browser.cache.memory.max_entry_size", 51200); // 50 MB per object
user_pref("media.memory_cache_max_size", 262144); // 256 MB media buffer

user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.sessionhistory.max_entries", 20);

user_pref("dom.ipc.processCount", 8);

user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", false);
user_pref("gfx.webrender.all", true);
user_pref("widget.dmabuf.wayland.enabled", false);
EOF
)

# Pref yang dikelola script ini. Baris lama untuk key ini dibuang supaya tidak dobel/konflik.
MANAGED_KEYS='browser.cache.disk.enable
browser.cache.disk.capacity
browser.cache.disk.smart_size.enabled
browser.cache.memory.enable
browser.cache.memory.capacity
browser.cache.memory.max_entry_size
media.memory_cache_max_size
browser.tabs.unloadOnLowMemory
browser.sessionhistory.max_entries
browser.sessionhistory.max_total_viewers
dom.ipc.processCount
media.ffmpeg.vaapi.enabled
media.hardware-video-decoding.force-enabled
gfx.webrender.all
widget.dmabuf.wayland.enabled'

render_user_js() {
    local target="$1"
    local tmp
    tmp=$(mktemp)

    if [ -f "$target" ]; then
        MANAGED_KEYS="$MANAGED_KEYS" \
        BEGIN_MARK="$BEGIN_MARK" \
        END_MARK="$END_MARK" \
        awk '
            BEGIN {
                n = split(ENVIRON["MANAGED_KEYS"], keys, "\n")
                for (i = 1; i <= n; i++) managed[keys[i]] = 1
            }
            $0 == ENVIRON["BEGIN_MARK"] { inblock = 1; next }
            $0 == ENVIRON["END_MARK"] { inblock = 0; next }
            inblock { next }
            {
                line = $0
                for (k in managed) {
                    if (index(line, "user_pref(\"" k "\"") == 1) next
                }
                # komentar header blok versi lama
                if (line ~ /^\/\/ (High RAM Multi-Tab|1\. Zero Disk Cache|2\. Disable Tab Sleeping|3\. Multi-Process Concurrency|4\. Hardware Video Acceleration)/) next
                if (line ~ /bfcache: keep 20 pages|memory cache in RAM per profile|media stream buffer|100MB per object/) next
                if (line ~ /^[[:space:]]*$/) { if (!printed) next } else { printed = 1 }
                print line
            }
        ' "$target" > "$tmp"
    else
        : > "$tmp"
    fi

    # rapikan baris kosong beruntun di akhir
    awk 'BEGIN{blank=0} {if ($0=="") {blank++} else {while (blank>0) {print ""; blank--}}} {if ($0!="") print}' "$tmp" > "$tmp.trim"
    cat "$tmp.trim" > "$target"
    rm -f "$tmp" "$tmp.trim"

    # pastikan ada newline sebelum blok
    if [ -s "$target" ] && [ -n "$(tail -c 1 "$target")" ]; then
        printf '\n' >> "$target"
    fi
    {
        printf '%s\n' "$BEGIN_MARK"
        printf '%s\n' "$BLOCK"
        printf '%s\n' "$END_MARK"
    } >> "$target"
}

echo "[+] Scanning for Firefox profiles..."
PROFILE_DIRS=()
for base in "$HOME/.mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox"; do
    [ -d "$base" ] || continue
    while IFS= read -r -d '' p; do
        PROFILE_DIRS+=("$p")
    done < <(find "$base" -maxdepth 1 -mindepth 1 -type d -name "*.*" ! -name "*.zap-client-profile" -print0)
done

if [ ${#PROFILE_DIRS[@]} -eq 0 ]; then
    echo "[!] No Firefox profile directories found."
    exit 0
fi

for p in "${PROFILE_DIRS[@]}"; do
    render_user_js "$p/user.js"
    echo "[+] user.js updated (idempoten): $(basename "$p")"
done

echo "[+] Firefox prefs managed for ${#PROFILE_DIRS[@]} profiles. Restart Firefox agar berlaku."
