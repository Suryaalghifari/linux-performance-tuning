# 05. App & Desktop Acceleration

A tuned kernel and CPU can still feel sluggish if core desktop applications (VS Code and Firefox) fall back to CPU software rendering or thrash the disk with cache files.

---

## 1. VS Code: Forcing Hardware GPU Acceleration

By default on Linux under Wayland or Snap confinement, VS Code (Electron) often disables hardware acceleration and reports:
```text
2d_canvas:       disabled_software
gpu_compositing: disabled_software
```
This forces the CPU to calculate every font glyph, cursor blink, and editor scroll, consuming 15%–20% of CPU cycles that should be reserved for compilation, testing, and AI tools.

### Enabling Hardware Acceleration:
Launch arguments:
- `--enable-gpu-rasterization`: Offloads 2D layout and canvas rasterization to GPU compute units.
- `--enable-zero-copy`: Shares rasterized tiles directly with the compositor via DMA buffers without CPU memory copying.
- `--ignore-gpu-blocklist`: Bypasses conservative Chromium driver blacklists for AMD Vega / Intel graphics.
- `--disk-cache-dir=/dev/shm/vscode-cache`: Directs Electron webview and extension cache to volatile RAM disk.

### Implementation for Snap / Desktop:
Place an override in `~/.local/share/applications/code_code.desktop`:
```ini
[Desktop Entry]
X-SnapInstanceName=code
Name=Visual Studio Code
Exec=/snap/bin/code --force-user-env --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --disk-cache-dir=/dev/shm/vscode-cache %F
Icon=/snap/code/current/meta/gui/vscode.png
Type=Application
StartupWMClass=code_code
```

### CLI Shell Integration (Fish / Bash):
To suppress the Chromium warning (`Warning: 'enable-gpu-rasterization' is not in the list of known options...`) when running `code .` from terminal:
```fish
# In ~/.config/fish/config.fish
function code
    command /snap/bin/code --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --disk-cache-dir=/dev/shm/vscode-cache $argv 2>&1 | string match -v "*is not in the list of known options*"
end
```

---

## 2. Firefox: Cache, Multi-Tab, & VA-API Video Acceleration

Firefox default menulis cache ke SSD dan menahan memori lebih agresif. Konfigurasi di bawah
adalah hasil kalibrasi ulang untuk 16–18 GiB RAM / 4 thread setelah insiden screencast crash
(lihat `docs/09-incident-firefox-meet-crash.md`).

Aturan penting: **jangan** memaksa jalur DMA-BUF Wayland atau `hardware-video-decoding.force-enabled`.
Di Wayland + Mesa + Vega 3 kombinasi itu bikin Firefox SIGSEGV di jalur screencast PipeWire
saat "Stop sharing" di Google Meet.

### Prefs yang dipakai (`scripts/setup-firefox-ram.sh` menulis blok managed ke `user.js`)
```javascript
// Cache: disk cache kecil + RAM cache moderat (bukan 2 GB)
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 262144);   // 256 MB
user_pref("browser.cache.memory.capacity", 524288); // 512 MB
user_pref("browser.cache.memory.max_entry_size", 51200);
user_pref("media.memory_cache_max_size", 262144);   // 256 MB

// Tab & proses
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.sessionhistory.max_entries", 20);
user_pref("dom.ipc.processCount", 8);               // 4 thread: jangan 16

// Video: VA-API aktif, tapi jangan dipaksa
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", false);
user_pref("gfx.webrender.all", true);
user_pref("widget.dmabuf.wayland.enabled", false);
```

`scripts/setup-firefox-ram.sh` bersifat idempoten: blok lama dibuang dan diganti blok baru,
prefs custom user di luar blok managed tidak disentuh. Restart Firefox setelah menjalankannya.

### Verification:
Navigate to `about:support` in Firefox:
- **Compositing**: `WebRender`
- **Hardware H264 / VP9 Decoding**: `Supported`
Playing 4K/1080p60 YouTube videos will now utilize <5% CPU instead of 40%+.
