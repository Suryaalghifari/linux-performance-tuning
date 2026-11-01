# Documentation Index

This directory contains in-depth technical explanations of the hardware registers, kernel mechanics, memory topologies, and application runtime behaviors optimized in this repository.

---

## 📚 Reading Path

1. **[01. Prerequisites & Security Gates](./01-prerequisites.md)**
   - Secure Boot, OEM BIOS quirks (HP 4-digit PIN confirmation), Kernel Lockdown, and MSR user-space write enablement.
2. **[02. AMD Zen / APU Hardware Tuning](./02-amd-cpu-tuning.md)**
   - Overclocking locked mobile CPUs via MSR P-State tables (`amdctl`), SMU mailbox overrides (`ryzenadj`), STAPM vs PPT, and thermal dissipation bounds.
3. **[03. Intel Core Tuning Guide](./03-intel-cpu-tuning.md)**
   - Intel RAPL PL1/PL2 power limits, MSR undervolting via `intel-undervolt`, `thermald` management, and Speed Shift / EPP configuration.
4. **[04. Memory Topology & ZRAM Tiering](./04-ram-and-zram.md)**
   - Asymmetric Dual-Channel (Flex Mode) for APU iGPU bandwidth, DDR4 IMC downclocking rules, ZRAM zstd compression tiering, and dirty memory buffering.
5. **[05. App & Desktop Acceleration](./05-app-acceleration.md)**
   - Electron & VS Code GPU rasterization overrides, Snap confinement workarounds, volatile RAM disk caching (`/dev/shm`), and Firefox multi-profile RAM caching with VA-API hardware video decode.
6. **[06. Network & Kernel Optimization](./06-network-and-system.md)**
   - Google TCP BBR congestion control, inotify file watcher limits for large git repos, and systemd journal disk write caps.
7. **[07. Telemetry & Monitoring Guide](./07-telemetry-and-monitoring.md)**
   - Why `/proc/cpuinfo` misleads due to C-state sleep averaging, measuring real crystal clocks via `turbostat`, and setting up GNOME Shell top bar telemetry.
