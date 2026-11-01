# Linux Hardware & System Performance Tuning Playbook

Automated playbooks, hardware register modifications, kernel optimizations, and system tuning guides for squeezing peak sustained performance out of locked CPUs (AMD Zen/Picasso & Intel Core), RAM, GPU acceleration, and I/O subsystems on Ubuntu and Debian-based Linux desktops.

![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%2B-orange?logo=ubuntu)
![Linux Kernel](https://img.shields.io/badge/Linux_Kernel-6.x%20%7C%207.x-blue?logo=linux)
![License](https://img.shields.io/badge/License-MIT-green)
![AMD Zen & Intel](https://img.shields.io/badge/Hardware-AMD_Zen%20%7C%20Intel_Core-red)

---

## 🎯 Architecture & Execution Flow

```mermaid
flowchart TD
    A[Start: Linux Performance Tuning] --> B[Phase 1: Security & Kernel Unlock]
    B --> B1[Disable Secure Boot in BIOS]
    B1 --> B2[Confirm 4-digit OEM PIN]
    B2 --> B3[Unlock MSR: allow_writes=on]
    
    B3 --> C{CPU Vendor Detection}
    
    C -->|AMD Zen / APU| D1[AMD Tuning Engine]
    D1 --> D2[Hack MSR P-State via amdctl\nP0=3.3GHz, P1=3.0GHz]
    D2 --> D3[Bypass SMU TDP via ryzenadj\nSTAPM 20W, FAST 24W, Temp 90C]
    D3 --> D4[Lock scaling_min_freq & Performance Governor]
    
    C -->|Intel Core| E1[Intel Tuning Engine]
    E1 --> E2[intel-undervolt / MSR Offset]
    E2 --> E3[Adjust RAPL PL1 & PL2 Power Limits]
    E3 --> E4[Configure thermald & Performance Governor]
    
    D4 --> F[Phase 3: Memory & Storage Tiering]
    E4 --> F
    
    F --> F1[ZRAM 8GB zstd Priority 100]
    F1 --> F2[Demote SSD Swap to Priority 5 Fallback]
    F2 --> F3[Tweak Sysctl: swappiness=60, dirty_ratio=15]
    
    F3 --> G[Phase 4: App & I/O Acceleration]
    G --> G1[VS Code: Force GPU Rasterization & /dev/shm Cache]
    G1 --> G2[Firefox: Zero Disk Cache & VA-API Hardware Decode]
    G2 --> G3[Kernel: inotify 524k & Google TCP BBR Network]
    G3 --> G4[Journald: Cap log disk usage to 100MB]
    
    G4 --> H[Phase 5: Systemd Persistence Engine]
    H --> H1[linux-boost.service on Boot / Resume]
    H1 --> H2[linux-boost.timer every 30s to defeat OEM EC Reset]
    H2 --> I[End: Max Sustained Hardware Speed]
```

---

## 📊 AMD vs Intel Optimization Matrix

| Optimization Vector | AMD APU (Zen / Zen+ / Picasso) | Intel Core (8th - 13th Gen) |
| :--- | :--- | :--- |
| **P-State Overclock** | Direct MSR overwrite (`0xC0010064` via `amdctl`). Modifies base FID/DID. | Multiplier locked on non-K; use BCLK or Turbo Ratio limits if unlocked. |
| **Power Limit (TDP)** | SMU Mailbox bypass via `ryzenadj` (STAPM, PPT FAST, PPT SLOW). | MSR `0x610` (MSR_PKG_POWER_LIMIT) via RAPL or `intel-undervolt`. |
| **Undervolting** | Register VID manipulation in P-State tables. | Direct voltage offset via MSR `0x150` (Core, Cache, Uncore, iGPU). |
| **Memory Topology** | Critical: Flex Dual Channel required for Radeon Vega iGPU bandwidth. | Dual Channel recommended for Intel UHD/Iris Xe graphics. |
| **EC Reset Defense** | Systemd timer required (30s interval) to counter HP/Lenovo power resets. | Systemd timer required to counter Intel DPTF / OEM thermal manager resets. |
| **Kernel Prerequisites** | Secure Boot OFF + `allow_writes=on` on `/sys/module/msr`. | Secure Boot OFF + `msr` module enabled. |

---

## 📁 Repository Structure

- [`docs/`](./docs/README.md) - Deep dive guides explaining the physics, registers, and kernel mechanisms.
- [`scripts/`](./scripts/README.md) - Modular automation scripts for hardware tuning, ZRAM setup, and app acceleration.
- [`systemd/`](./systemd/README.md) - Systemd unit files and anti-EC reset defense timers.
- [`configs/`](./configs/README.md) - Production sysctl, desktop, and journald configuration templates.

---

## 🚀 Quick Start (Automated Installation)

Clone this repository and run the unified installer:

```bash
git clone https://github.com/Suryaalghifari/linux-performance-tuning.git
cd linux-performance-tuning
chmod +x scripts/*.sh

# Run the installer (interactive or automatic detection)
sudo ./scripts/install.sh
```

---

## 🔍 Verification & Telemetry

Don't rely on `/proc/cpuinfo` under `acpi-cpufreq` as it averages duty cycles during C-state sleep. Verify real hardware execution clocks using `turbostat`:

```bash
sudo turbostat -s Bzy_MHz,TSC_MHz,Busy%,PkgWatt -i 1
```

- **`TSC_MHz`**: Shows true physical crystal clock (e.g. `3294 MHz` = 3.3 GHz locked).
- **`Bzy_MHz`**: Shows actual unhalted core frequency under execution load.
- **`PkgWatt`**: Shows package power draw under tuned limits.

---

## 🛡️ Rollback & Safety

To revert all changes back to standard factory defaults:

```bash
sudo ./scripts/uninstall.sh
```

---

## 📜 License

MIT License. Crafted for developers, DevOps engineers, and Linux power users seeking to maximize hardware lifespan and workstation responsiveness.
