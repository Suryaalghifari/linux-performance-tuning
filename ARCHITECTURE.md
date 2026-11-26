# System Architecture & Tuning Flow

Blueprint arsitektur teknis optimasi performa Linux Ubuntu pada laptop spek hemat (AMD APU Zen/Picasso & Intel Core).

---

## Architecture Flowchart

```mermaid
flowchart TB
    %% =========================================================================
    %% Linux Performance Tuning - System Architecture & Execution Blueprint
    %% =========================================================================

    subgraph SEC["1. Security and Kernel Gates"]
        direction TB
        BIOS["OEM BIOS<br/>Disable Secure Boot"]
        PIN["HP / OEM Firmware<br/>Confirm 4-Digit Unlock PIN"]
        K_LOCK["Linux Kernel Lockdown<br/>Transition to none"]
        MSR_W["MSR Module<br/>allow_writes = on"]

        BIOS --> PIN
        PIN --> K_LOCK
        K_LOCK --> MSR_W
    end

    subgraph HARDWARE["2. CPU Registers and SMU Engine"]
        direction TB
        CPU_CHECK{"CPU Vendor<br/>Detection"}

        subgraph AMD_PATH["AMD Zen and Picasso APU Engine"]
            direction TB
            AMD_MSR["P-State dari firmware<br/>Tidak override MSR (amdctl hanya untuk inspeksi)"]
            AMD_SMU["SMU Mailbox via ryzenadj<br/>STAPM 15W / FAST 20W / Ceiling 85C"]
            AMD_GOV["CPUFreq Governor<br/>schedutil + min P-state terendah (1.4 GHz)"]
            AMD_MSR --> AMD_SMU --> AMD_GOV
        end

        subgraph INTEL_PATH["Intel Core Engine"]
            direction TB
            INTEL_MSR["MSR 0x150 via intel-undervolt<br/>Core, Cache and iGPU Voltage Offset"]
            INTEL_RAPL["RAPL MSR 0x610 Limits<br/>Adjust PL1 Sustained and PL2 Burst"]
            INTEL_GOV["Energy Performance Preference<br/>performance / thermald Rules"]
            INTEL_MSR --> INTEL_RAPL --> INTEL_GOV
        end

        CPU_CHECK -->|AMD Vendor| AMD_MSR
        CPU_CHECK -->|Intel Vendor| INTEL_MSR
    end

    subgraph MEMORY["3. Memory Hierarchy and Storage Tiering"]
        direction TB
        RAM_TOPO["Physical RAM: 17.5 GiB<br/>MemTotal 18,324,392 kB"]

        ZRAM_DEV["Tier 1: /dev/zram0<br/>8 GB zstd In-Memory Swap (Priority 100)"]
        SSD_DEV["Tier 2: /swap.img<br/>SSD Swap Demoted to Fallback (Priority 5)"]

        SYSCTL_VM["Sysctl Virtual Memory Tuning<br/>swappiness = 60 / vfs_cache_pressure = 10<br/>dirty_ratio = 10 / dirty_background = 5"]
        NVME_RA["NVMe I/O Subsystem<br/>read_ahead_kb = 1024 KB"]

        RAM_TOPO --> ZRAM_DEV
        ZRAM_DEV -.->|Overflow Only| SSD_DEV
        RAM_TOPO --> SYSCTL_VM
        SYSCTL_VM --> NVME_RA
    end

    subgraph APPS["4. Application and Desktop Acceleration"]
        direction TB
        DEV_SHM["RAM Disk Buffer<br/>/dev/shm (Shared Memory)"]

        VSCODE["VS Code IDE Launcher<br/>--enable-gpu-rasterization<br/>--disk-cache-dir = /dev/shm/vscode-cache"]
        FIREFOX["Firefox Profile (managed block)<br/>RAM cache 512 MB / disk cache 256 MB<br/>VA-API decode (tanpa force) + dmabuf Wayland off"]
        SYSTEM_OPT["Kernel OS Tweaks<br/>fs.inotify.max_user_watches = 524288<br/>TCP BBR + Fair Queueing (fq)<br/>Journald Log Size Capped at 512 MB"]

        DEV_SHM --> VSCODE
        DEV_SHM --> FIREFOX
        SYSTEM_OPT
    end

    subgraph PERSIST["5. Systemd Persistence Engine"]
        direction TB
        SVC["linux-boost.service<br/>Re-asserts Hardware Clocks on Boot and Resume"]
        TMR["linux-boost.timer<br/>Re-asserts hourly + on Boot/Resume"]
        EC_EVENT["OEM Embedded Controller (EC)<br/>AC Adapter Plug and Unplug Events"]

        EC_EVENT -.->|Triggers 15W Power Reset| SVC
        TMR -->|Periodic Re-assertion| SVC
    end

    subgraph TELEMETRY["6. Telemetry and Verification"]
        direction TB
        TURBO["turbostat Telemetry<br/>Measures Real Hardware TSC_MHz and PkgWatt"]
        NO_PROC["Avoid /proc/cpuinfo<br/>Misleads due to C-state sleep averaging"]
        TURBO -.->|Accurate Metric| NO_PROC
    end

    %% Inter-Tier Connections (Forward Only)
    MSR_W --> CPU_CHECK
    AMD_GOV --> RAM_TOPO
    INTEL_GOV --> RAM_TOPO
    SYSCTL_VM --> APPS
    NVME_RA --> DEV_SHM
    APPS --> SVC
    SVC --> TURBO
```

---

## Ringkasan 6 Layer Arsitektur

1. **Security & Kernel Gates**: Unlock MSR user-space write dan matikan kernel lockdown via BIOS Secure Boot OFF.
2. **CPU Registers & SMU Engine**: P-state dibiarkan sesuai firmware (override MSR tidak dipakai karena CPU hanya mengekspos 3 P-state), batas TDP diatur via ryzenadj (15 W STAPM, ceiling 85 °C).
3. **Memory Hierarchy & Storage Tiering**: 17.5 GiB RAM + 8 GB ZRAM zstd priority 100. SSD swap turun ke priority 5, tanpa swapoff berkala.
4. **App & Desktop Acceleration**: VS Code GPU rasterization + cache ke `/dev/shm`. Firefox RAM cache 512 MB, disk cache 256 MB, VA-API tanpa force, dmabuf Wayland off (hindari crash screencast).
5. **Systemd Persistence Engine**: `linux-boost.service` dan `linux-boost.timer` (boot/resume + interval 1 jam) melawan reset daya dari Embedded Controller (EC).
6. **Telemetry & Verification**: Pengukuran clock kristal fisik valid via `turbostat` (hindari distorsi `/proc/cpuinfo`).
