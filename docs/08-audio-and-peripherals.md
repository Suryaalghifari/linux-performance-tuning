# 08. Audio, Peripherals & Ground Loop Noise Mitigation

Aggressive CPU tuning, high TDP limits, and governor locks can inadvertently degrade analog audio input quality on laptops sharing unshielded motherboard traces. This document explains the electrical causes and provides targeted software and ALSA mitigations.

---

## 1. Electrical Root Cause: EMI & Ground Loops Post-Tuning

When you apply aggressive hardware optimizations:
1. **CPU Frequency & VRM Switching**:
   - Locking CPU frequency (`scaling_governor=performance`) and lifting SMU limits via `ryzenadj` or `intel-undervolt` forces CPU Voltage Regulator Modules (VRM) to run at high continuous switching currents.
2. **Motherboard Trace Proximity**:
   - On thin-and-light laptops (e.g. HP 14/15 series with Realtek ALC236), the analog 3.5mm combo jack and microphone traces run physically parallel to motherboard power planes without specialized galvanic isolation.
   - Switching ripples from the VRM induce high-frequency electromagnetic interference (EMI) directly into the microphone trace.
3. **AC Charger Ground Loop**:
   - Running on AC adapter power grounds the chassis through the power supply. Small voltage differentials between the charger ground and audio ground produce a 50Hz/60Hz hum combined with high-pitch coil whine.

---

## 2. The Linux Jack-Sense Gain Trap (+60 dB Overboost)

The most severe contributor to meeting noise is not the electrical hardware alone, but ALSA's default mixer gain mapping upon jack insertion:

### Measured ALSA ALC236 Gain Profile:
- **`Mic Boost Volume`**: Defaults to level `3` (max **+30.00 dB**).
- **`Capture Volume`**: Defaults to index `63` (max **+30.00 dB**, where index 23 is unity 0.00 dB).

$$\text{Total Analog Gain} = +30.00\,\text{dB} + 30.00\,\text{dB} = \mathbf{+60.00\,\text{dB}}$$

Applying **+60.00 dB** of hardware preamplification multiplies microvolt-level background thermal and EMI noise by **1,000x**. In web conference platforms (Google Meet, Zoom, Discord), this manifests as an overpowering white noise hiss, jet engine background hum, and voice clipping.

---

## 3. Kernel Codec Power Saving (`snd_hda_intel`)

Linux distributions enable power saving on HD-Audio controllers by default:
- `snd_hda_intel.power_save = 1`
- `snd_hda_intel.power_save_controller = Y`

### Impact on Analog Audio:
- The kernel cuts power to the DAC/ADC precisely 1 second after an audio stream closes.
- When an application (or browser tab) resumes recording or playback, the sudden capacitor charge creates an audible **pop / click**.
- While entering or leaving sleep states, the floating input impedance causes a characteristic fluctuating buzz.

---

## 4. Mitigation Strategy

### Step 1: Clamp Hardware Preamp Gain
Reduce the hardware amplification to a balanced sweet spot:
- Set **`Mic Boost`** to level `1` (+10.00 dB) or `0` (0.00 dB).
- Set **`Capture`** to index `45` (+16.50 dB / ~71%) instead of 63 (+30.00 dB).

This achieves a **~33.5 dB reduction in noise floor**, dropping electrical and fan noise below the threshold of audibility while maintaining crisp, undistorted vocal volume.

```bash
# Apply to targeted audio card (card 1 for ALC236)
amixer -c 1 sset 'Mic Boost' 1
amixer -c 1 sset 'Capture' 45
```

### Step 2: Disable Kernel Audio Power Saving
Prevent the audio hardware from sleeping and popping by deploying a modprobe configuration:

Create `/etc/modprobe.d/audio-powersave.conf`:
```ini
options snd_hda_intel power_save=0 power_save_controller=N
```

Apply immediately at runtime:
```bash
echo 0 | sudo tee /sys/module/snd_hda_intel/parameters/power_save
echo N | sudo tee /sys/module/snd_hda_intel/parameters/power_save_controller
```

### Step 3: Persist Mixer States
Ensure ALSA restores these balanced levels across reboots:
```bash
sudo alsactl store 1
```

---

## 5. Automated Tuning Script

Run the automated audio optimization script from the repository:
```bash
# As standard user (mixer gain balance)
./scripts/tune-audio.sh

# With sudo (includes kernel modprobe power_save=0 persistence)
sudo ./scripts/tune-audio.sh
```
