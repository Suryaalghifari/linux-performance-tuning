# Configuration Templates

This directory houses static configuration templates deployed to system directories during the installation process.

---

## 📁 File Manifest

| File | Target Path | Description |
| :--- | :--- | :--- |
| **`99-performance.conf`** | `/etc/sysctl.d/99-performance.conf` | Kernel virtual memory management, filesystem inotify limits, and TCP BBR network parameters. |
| **`journald-size.conf`** | `/etc/systemd/journald.conf.d/00-limit-size.conf` | Batasi journal 512 MB. 100 MB terlalu kecil: log 2 hari sudah hilang sehingga insiden (crash/OOM/thermal) tidak bisa dibuktikan. |
| **`code_code.desktop`** | `~/.local/share/applications/code_code.desktop` | Override desktop entry launching VS Code with GPU rasterization and RAM disk caching. |
| **`audio-powersave.conf`** | `/etc/modprobe.d/audio-powersave.conf` | Disables kernel `snd_hda_intel` power save to stop audio pops, clicks, and idle noise on analog jacks. |
| **`rtw88-deep-lps.conf`** | `/etc/modprobe.d/rtw88-deep-lps.conf` | Matikan deep LPS RTL8821CE (`disable_lps_deep=Y`). Firmware gagal keluar dari deep sleep: log spam 32x/menit + jitter WiFi sampai 150 ms. |
