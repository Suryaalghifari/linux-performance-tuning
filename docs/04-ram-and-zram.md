# 04. Memory Topology & ZRAM Tiering

Memory bottlenecks degrade Linux workstation performance more noticeably than raw CPU limitations. When physical RAM is exhausted, traditional disk swap leads to system freezing, dropped desktop frames, and terminal latency.

---

## 1. Physical RAM Topology: Asymmetric Flex Dual Channel

Integrated GPUs (AMD Radeon Vega and Intel Iris Xe) do not have dedicated VRAM; they carve out frame buffer space directly from system RAM.

### Channel Bandwidth Impact:
- **Single Channel (64-bit bus)**: Data transfer rate is halved. iGPU performance drops by 40%–50%, causing mouse lag and frame drops when driving external high-resolution monitors (e.g. 24" 1080p/1440p).
- **Symmetric Dual Channel (e.g., 8GB + 8GB)**: Full 128-bit bus width across all addresses.
- **Asymmetric Flex Dual Channel (e.g., 4GB + 16GB = 20GB)**:
  - The first **8 GB** (4GB from Slot 1 + 4GB from Slot 2) runs in high-speed 128-bit Dual Channel mode.
  - The remaining **12 GB** runs in 64-bit Single Channel mode.
  - **Verdict**: Far superior to running a single 16GB stick alone. iGPU and critical desktop buffers reside in the dual-channel region.

### Integrated Memory Controller (IMC) Clocks:
On Zen+ (Picasso) mobile chips, the IMC is hardware-capped at **2400 MT/s**. Installing 3200 MT/s DDR4 modules will automatically downclock to 2400 MT/s. The benefit: memory timings (CAS latency) automatically tighten, providing optimal stability and lower latency.

---

## 2. ZRAM: Compressed In-Memory Swap

Traditional swap files on NVMe or SATA SSDs are 100x to 1000x slower than RAM and cause heavy write wear. ZRAM creates a virtual block device in RAM where pages are compressed on the fly (typically achieving 2.5:1 to 3:1 compression ratios with `zstd`).

### ZRAM Configuration (8 GB Block Device):
```bash
# Load module
modprobe zram num_devices=1

# Configure 8GB size with zstd algorithm
zramctl /dev/zram0 --size 8G --algorithm zstd

# Format and mount as high-priority swap
mkswap /dev/zram0
swapon -p 100 /dev/zram0
```

### Two-Tier Swap Priority:
```text
Tier 1: /dev/zram0 (Priority 100) -> 8 GB RAM compressed buffer (ultra-fast)
Tier 2: /swap.img   (Priority 5)   -> SSD swap file (emergency overflow only)
```
The Linux kernel fills `/dev/zram0` first. The SSD swap file is never touched during normal high-load multitasking, eliminating disk thrashing completely.

---

## 3. Kernel Virtual Memory (`sysctl`) Tuning

With 16GB+ RAM and ZRAM in place, default Linux virtual memory parameters must be recalibrated:

```ini
# /etc/sysctl.d/99-performance.conf

# Keep swappiness at 60 to actively push idle memory into fast ZRAM,
# freeing uncompressed physical RAM for active apps and disk cache.
vm.swappiness = 60

# Prevent kernel from prematurely discarding inode/dentry file caches
vm.vfs_cache_pressure = 50

# Flush dirty pages to disk in small, frequent background writes
# to prevent desktop micro-stutters during heavy disk operations.
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
```
