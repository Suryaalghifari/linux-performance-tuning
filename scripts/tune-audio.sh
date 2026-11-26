#!/usr/bin/env bash
# Audio tuning script for Realtek ALC236 & Analog 3.5mm Headset
# Eliminates high-frequency noise, buzzing, and popping caused by over-amplification & power saving
set -euo pipefail

echo "[+] Starting Audio & Headset Noise Mitigation..."

# 1. Locate the analog audio card index (e.g. Realtek ALC236)
CARD_INDEX=""
for card_path in /proc/asound/card[0-9]*; do
    if [ -d "$card_path" ]; then
        idx=$(basename "$card_path" | sed 's/card//')
        if grep -qi "ALC\|Realtek\|Analog" "$card_path/codec#"* 2>/dev/null || aplay -l 2>/dev/null | grep -q "card $idx:.*Analog"; then
            CARD_INDEX="$idx"
            break
        fi
    fi
done

if [ -z "$CARD_INDEX" ]; then
    echo "[!] Could not auto-detect specific codec, defaulting to card 1..."
    CARD_INDEX="1"
fi

echo "[+] Targeted Audio Card: $CARD_INDEX"

# 2. Adjust Hardware Mic Boost (clamp to 10.00 dB instead of +30.00 dB)
if amixer -c "$CARD_INDEX" scontrols 2>/dev/null | grep -q "'Mic Boost'"; then
    amixer -c "$CARD_INDEX" sset 'Mic Boost' 1 >/dev/null 2>&1 || true
    echo "[+] Clamped 'Mic Boost' to level 1 (+10.00 dB) to eliminate preamp floor hiss."
fi

# 3. Adjust Hardware Capture Volume (clamp to 45 / ~71% instead of 63 / 100% / +30 dB)
if amixer -c "$CARD_INDEX" scontrols 2>/dev/null | grep -q "'Capture'"; then
    amixer -c "$CARD_INDEX" sset 'Capture' 45 >/dev/null 2>&1 || true
    echo "[+] Balanced 'Capture' volume to 45 (+16.50 dB) to prevent audio distortion and clipping."
fi

# 4. Save ALSA Mixer State
if command -v alsactl >/dev/null 2>&1; then
    alsactl store "$CARD_INDEX" 2>/dev/null || alsactl -f "$HOME/.asound.state" store "$CARD_INDEX" 2>/dev/null || true
    echo "[+] Persisted ALSA mixer state."
fi

# 5. Disable Audio Power Save (requires root for kernel sysfs & modprobe)
if [ "$(id -u)" -eq 0 ]; then
    if [ -f /sys/module/snd_hda_intel/parameters/power_save ]; then
        echo 0 > /sys/module/snd_hda_intel/parameters/power_save
        echo N > /sys/module/snd_hda_intel/parameters/power_save_controller || true
        echo "[+] Disabled runtime snd_hda_intel power save (prevents popping & idle hum)."
    fi

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"
    if [ -f "$REPO_ROOT/configs/audio-powersave.conf" ]; then
        cp "$REPO_ROOT/configs/audio-powersave.conf" /etc/modprobe.d/audio-powersave.conf
        echo "[+] Deployed persistent modprobe config to /etc/modprobe.d/audio-powersave.conf."
    fi
else
    echo "[i] Note: To permanently disable kernel audio power-saving (pop/click defense), run this script with sudo."
fi

echo "[+] Audio tuning successfully applied!"
