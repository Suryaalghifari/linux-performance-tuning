# Scripts Directory

This directory contains standalone, modular bash scripts that execute each optimization phase. They can be invoked independently for targeted tuning or run in sequence via `install.sh`.

---

## 📜 Script Manifest

| Script | Purpose | Execution Context |
| :--- | :--- | :--- |
| **`install.sh`** | Unified installer; auto-detects CPU (AMD vs Intel), installs dependencies, and enables systemd persistence. | `sudo ./scripts/install.sh` |
| **`uninstall.sh`** | Complete rollback script; stops timers, unmounts ZRAM, and restores default kernel parameters. | `sudo ./scripts/uninstall.sh` |
| **`amd-tune-hardware.sh`** | Worker script that overrides AMD MSR P-States, sets SMU power limits via `ryzenadj`, and tunes scaling governors. | Invoked by systemd timer or root CLI |
| **`intel-tune-hardware.sh`** | Intel RAPL power cap adjuster and governor configuration helper. | Invoked by systemd timer or root CLI |
| **`setup-zram.sh`** | Sets up `/dev/zram0` (8GB zstd) with priority 100 and demotes SSD swap to fallback priority 5. | Root CLI |
| **`setup-vscode-gpu.sh`** | Generates the VS Code desktop launcher override with GPU flags and installs the Fish shell function. | User CLI |
| **`setup-firefox-ram.sh`** | Injects zero-disk RAM caching and VA-API hardware decoding into all discovered Firefox user profiles. | User CLI |
