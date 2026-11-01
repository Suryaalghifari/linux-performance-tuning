# 07. Telemetry & Monitoring Guide

Accurate hardware measurement is critical when overclocking or unlocking mobile CPUs. Traditional monitoring tools often provide misleading or contradictory metrics.

---

## 1. Why `/proc/cpuinfo` & `lscpu` Mislead

Under Linux's `acpi-cpufreq` driver, reading `/proc/cpuinfo` or running `lscpu` often reports numbers lower than expected (e.g. 2.1 GHz when overclocked to 3.3 GHz).

### The C-State Duty Cycle Averaging Problem:
- In modern processors, idle cores enter deep sleep states (C1, C2, C6).
- When you execute a lightweight command like `watch -n 1 grep MHz /proc/cpuinfo`, the processor is actually working for only **10% of the sample period** and sleeping for the remaining 90%.
- Linux calculates frequency using the hardware APERF/MPERF ratio:
  $$\text{Effective MHz} = \frac{\text{APERF}}{\text{MPERF}} \times \text{Base MHz}$$
- The reported frequency is mathematically dragged down because the core was asleep for most of the window.
- Furthermore, OEM ACPI tables often advertise a hardcoded 2.40 GHz nominal maximum to the kernel, capping the reported frequency ceiling in user tools.

---

## 2. Real Telemetry: Using `turbostat`

`turbostat` (part of `linux-tools-common`) directly reads the CPU's MSR crystal counters and hardware duty cycles.

### Monitoring Command:
```bash
sudo turbostat -s Bzy_MHz,TSC_MHz,Busy%,PkgWatt,CoreTmp -i 1
```

### Key Metrics Decoded:
- **`TSC_MHz`**: **Time Stamp Counter Clock**. Shows the physical clock frequency driving the core timer. If you overrode P0 to 3.3 GHz via `amdctl`, `TSC_MHz` will report `3294` (3.30 GHz) unconditionally.
- **`Bzy_MHz`**: **Busy Frequency**. The true clock frequency of the core while actively executing instructions (ignoring idle/sleep intervals). Under load, this should match your tuned P0/P1 clocks.
- **`Busy%`**: The percentage of time the core spent in active C0 execution state versus sleep.
- **`PkgWatt`**: Real-time package electrical power consumption reported by SMU/RAPL sensors.

---

## 3. GNOME Desktop Telemetry (Vitals Extension)

To monitor CPU clocks directly on the GNOME Shell top panel without opening a terminal:

1. Install the **Vitals** extension (`Vitals@CoreCoding.com`).
2. Configure hot sensors via `gsettings`:
   ```bash
   gsettings --schemadir ~/.local/share/gnome-shell/extensions/Vitals@CoreCoding.com/schemas \
     set org.gnome.shell.extensions.vitals hot-sensors \
     "['_processor_max_frequency_', '_processor_frequency_', '_temperature_k10temp_tctl_', '_memory_usage_']"
   ```
3. Use **Max Frequency** (`_processor_max_frequency_`) instead of average frequency to see peak core clock speeds accurately.
