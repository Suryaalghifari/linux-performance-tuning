# 06. Network & Kernel Optimization

This guide covers system-level optimizations for developers and DevOps engineers handling large repositories, proxy tools (`9router`), and active CLI sessions.

---

## 1. Google TCP BBR Congestion Control

Default Linux distributions use the `cubic` TCP congestion control algorithm, which aggressively throttles transfer rates on packet loss (common on Wi-Fi).

Google's **BBR (Bottleneck Bandwidth and RTT)** optimizes throughput based on estimated network capacity and round-trip time, delivering 15%–30% higher transfer speeds and lower connection latency for git fetches, docker image pulls, and proxy routing.

### Activation:
```bash
sudo modprobe tcp_bbr
sudo sysctl -w net.core.default_qdisc=fq
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
```

Persist in `/etc/sysctl.d/99-performance.conf`:
```ini
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

Verify:
```bash
sysctl net.ipv4.tcp_congestion_control
# Output: net.ipv4.tcp_congestion_control = bbr
```

---

## 2. Inotify File Watcher Expansion

Modern IDEs (VS Code, JetBrains) and file synchronizers use `inotify` to track filesystem events.
- **Default limit**: `65,536` files.
- **The Issue**: When opening large DevOps repos with `node_modules`, `.git`, or container files, inotify runs out of handles. The IDE silently falls back to **CPU polling**, scanning disk hierarchies repeatedly and causing terminal sluggishness and battery drain.

### Tuned Limits:
```bash
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
```

Persist in `/etc/sysctl.d/99-performance.conf`:
```ini
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

---

## 3. Systemd Journal Disk Write Caps

By default, `systemd-journald` can consume up to 4GB of disk space, constantly flushing logs to the root filesystem.

### Restricting Journal Disk Footprint:
Create `/etc/systemd/journald.conf.d/00-limit-size.conf`:
```ini
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=25M
RuntimeMaxUse=50M
```

Apply immediately:
```bash
sudo systemctl restart systemd-journald
sudo journalctl --vacuum-size=100M
```
This frees up hundreds of megabytes of SSD space and reduces background write overhead.
