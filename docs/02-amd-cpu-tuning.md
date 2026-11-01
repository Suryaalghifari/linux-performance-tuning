# 02. AMD Zen / APU Hardware Tuning

This guide covers mobile Zen/Zen+ processors (Picasso, Raven Ridge, e.g. Athlon Gold 3150U, Ryzen 3 3200U, Ryzen 5 3500U, Ryzen 7 3700U) where multipliers are locked by AMD, but hardware P-States and SMU power limits can be unlocked at runtime.

---

## 1. P-State Multiplier Hack via MSR (`amdctl`)

AMD Zen processors define power states (P0, P1, P2) in hardware MSRs starting at `0xC0010064`.
- **P0**: Highest performance state (Base clock).
- **P1**: Intermediate state.
- **P2**: Low-power idle state.

### Frequency Calculation Formula:
$$\text{Frequency (MHz)} = \left(\frac{\text{CpuFid}}{\text{CpuDid}}\right) \times 200$$

With standard divisor `CpuDid = 8`:
$$\text{Frequency (MHz)} = \text{CpuFid} \times 25$$

| Target Clock | CpuFid (Decimal) | CpuFid (Hex) | Usage |
| :--- | :--- | :--- | :--- |
| **2400 MHz** | 96 | 0x60 | Factory Stock P0 |
| **2800 MHz** | 112 | 0x70 | Mild Overclock |
| **3000 MHz** | 120 | 0x78 | Tuned P1 (Intermediate Lock) |
| **3300 MHz** | 132 | 0x84 | Tuned P0 (Peak Boost Lock) |

### Flat Clock Lock Strategy:
Modifying P0 alone allows the kernel governor to drop cores to factory P1 (1.7 GHz) or P2 (1.4 GHz) when partially idle, dragging effective clock down. To maintain flat 3.0–3.3 GHz clocks:
1. Reprogram **P0** to 3300 MHz:
   ```bash
   sudo ~/.local/bin/amdctl -m -p 0 -f 132
   ```
2. Reprogram **P1** to 3000 MHz:
   ```bash
   sudo ~/.local/bin/amdctl -m -p 1 -f 120 -d 8 -v 53
   ```
3. Clamp minimum scaling frequency:
   ```bash
   echo 2400000 | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq
   ```

---

## 2. SMU TDP Power Bypass via `ryzenadj`

The System Management Unit (SMU) enforces factory power limits (often 15W on thin laptops).

### Key SMU Power Limits:
- **`STAPM LIMIT`**: Skin Temperature Aware Power Management (sustained long-term package power).
- **`PPT LIMIT FAST`**: Immediate peak burst limit.
- **`PPT LIMIT SLOW`**: Sustained boost limit under load.
- **`THM LIMIT CORE`**: Silicon thermal ceiling (°C).

### Tuned Profile (HP 14s Sweet Spot):
```bash
sudo ryzenadj \
    --stapm-limit=20000 \
    --fast-limit=24000 \
    --slow-limit=20000 \
    --tctl-temp=90 \
    --max-performance
```

### Thermal Pitfalls:
1. **Setting Ceiling Too Low (e.g. 85°C)**: When ceiling is set lower than factory (90°C), the SMU aggressively throttles clocks down to 1.6 GHz on small spikes. Keep `--tctl-temp=90`.
2. **Pushing Sustained Power > 20W on 14" Single-Fan Heatsinks**: 25W sustained TDP causes junction temperature to reach 92°C, triggering hardware emergency throttling (PROCHOT). 20W sustained / 24W burst provides maximum sustained performance without hitting PROCHOT.

---

## 3. Defense Against OEM Embedded Controller (EC) Resets

Laptop Embedded Controllers (EC) monitor power state transitions (AC charger plugged vs battery). When AC is plugged or unplugged, the EC sends an interrupt that resets SMU limits back to 15W default.

**Solution**: Run a periodic systemd timer every 30 seconds (`linux-boost.timer`) to automatically re-assert P-State and SMU limits continuously.
