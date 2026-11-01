# Configuration Templates

This directory houses static configuration templates deployed to system directories during the installation process.

---

## 📁 File Manifest

| File | Target Path | Description |
| :--- | :--- | :--- |
| **`99-performance.conf`** | `/etc/sysctl.d/99-performance.conf` | Kernel virtual memory management, filesystem inotify limits, and TCP BBR network parameters. |
| **`journald-size.conf`** | `/etc/systemd/journald.conf.d/00-limit-size.conf` | Caps journal log growth to 100MB on disk to minimize SSD write wear. |
| **`code_code.desktop`** | `~/.local/share/applications/code_code.desktop` | Override desktop entry launching VS Code with GPU rasterization and RAM disk caching. |
