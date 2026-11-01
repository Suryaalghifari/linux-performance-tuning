# 03. Intel Core Tuning Guide

While AMD APUs utilize MSR P-States and SMU mailboxes, Intel Core processors (8th Gen through 13th Gen mobile/desktop) rely on Running Average Power Limit (RAPL), MSR voltage offsets, and thermal daemon controls.

---

## 1. Intel RAPL Power Limits (PL1 & PL2)

Intel mobile CPUs are frequently bottlenecked by aggressive power limits imposed by laptop manufacturers:
- **PL1 (Power Limit 1)**: Long-term sustained power limit (typically 15W–28W on U/P-series).
- **PL2 (Power Limit 2)**: Short-term turbo power limit (typically 25W–64W for 28 seconds).

### Adjusting RAPL via Linux sysfs:
Linux exposes power limits through `/sys/class/powercap/intel-rapl/`:
```bash
# Check current limits (in microwatts)
cat /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw
cat /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_1_power_limit_uw

# Example: Increase PL1 to 25W (25,000,000 uW) and PL2 to 35W (35,000,000 uW)
echo 25000000 | sudo tee /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw
echo 35000000 | sudo tee /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_1_power_limit_uw
```

---

## 2. Voltage Offsets (Undervolting via `intel-undervolt`)

Undervolting reduces power consumption and core temperature, allowing the processor to sustain higher Turbo Boost clocks before hitting thermal ceilings.

> **Note on Plundervolt**: Systems with BIOS updates after 2020 may have MSR `0x150` write locked. If locked, undervolting is ignored by hardware unless your BIOS permits disabling CPU Undervolt Protection.

### Installation & Configuration:
```bash
sudo apt install intel-undervolt
```

Edit `/etc/intel-undervolt.conf`:
```ini
undervolt 0 'CPU' -75
undervolt 1 'GPU' -40
undervolt 2 'CPU Cache' -75
undervolt 3 'System Agent' 0
undervolt 4 'Analog I/O' 0

# Apply power limits via intel-undervolt daemon
power package 25 35
```

Apply and verify:
```bash
sudo intel-undervolt apply
sudo intel-undervolt read
```

---

## 3. Managing `thermald` & DPTF Throttling

Intel Dynamic Platform and Thermal Framework (DPTF) can aggressively drop CPU clocks down to 800 MHz when chassis temperature rises.

1. Ensure `thermald` is installed:
   ```bash
   sudo apt install thermald
   sudo systemctl enable --now thermald
   ```
2. For aggressive OEM throttling policies (common on Dell/Lenovo), consider testing `--adaptive` mode or monitoring logs via:
   ```bash
   journalctl -u thermald -f
   ```

---

## 4. Intel Energy Performance Preference (EPP)

Under the `intel_pstate` driver, configure the hardware governor:
```bash
# Available preferences: default, performance, balance_performance, balance_power, power
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo performance | sudo tee "$epp"
done
```
