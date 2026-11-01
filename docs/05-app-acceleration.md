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

## 2. Firefox: RAM Cache & VA-API Video Acceleration

When opening 10+ tabs across multiple profiles, Firefox writes hundreds of megabytes of temporary cache to SSD storage, causing disk contention.

### Zero-Disk RAM Cache (`user.js`):
Inject into all Firefox profile directories (`~/.mozilla/firefox/*.default*` or `~/snap/firefox/common/.mozilla/firefox/*`):
```javascript
// user.js

// 1. Disable disk cache entirely
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.disk.smart_size.enabled", false);

// 2. Allocate 1GB in-memory cache per profile
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 1048576); // 1,048,576 KB = 1 GB
user_pref("browser.cache.memory.max_entry_size", 51200); // 50 MB
user_pref("media.memory_cache_max_size", 524288); // 512 MB media buffer

// 3. Enable hardware video decode via VA-API (Vega VCN engine)
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);
user_pref("gfx.webrender.all", true);
user_pref("widget.dmabuf.wayland.enabled", true);

// 4. Discard idle background tabs to conserve memory
user_pref("browser.tabs.unloadOnLowMemory", true);
```

### Verification:
Navigate to `about:support` in Firefox:
- **Compositing**: `WebRender`
- **Hardware H264 / VP9 Decoding**: `Supported`
Playing 4K/1080p60 YouTube videos will now utilize <5% CPU instead of 40%+.
