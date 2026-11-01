# 01. Prerequisites & Security Gates

Modern Linux kernels and OEM hardware implement security boundaries that intentionally restrict low-level hardware tuning. To gain direct access to CPU power tables and hardware registers, these gates must be unlocked.

---

## 1. Kernel Lockdown & Secure Boot

When UEFI Secure Boot is enabled, the Linux kernel activates **Kernel Lockdown** in `[integrity]` mode. In this state:
- Direct access to physical memory (`/dev/mem`) is blocked.
- Writing to CPU Model-Specific Registers (MSRs) via `/dev/cpu/*/msr` is forbidden.
- Raw PCI configuration space writes via `/sys/bus/pci/devices/*/config` are rejected.

### Verification Command:
```bash
cat /sys/kernel/security/lockdown
mokutil --sb-state
```
- If output is `[integrity]`, tuning tools like `ryzenadj` and `amdctl` will fail with errors such as `PCI Bus is not writeable`.
- Desired output: `[none]`.

---

## 2. Disabling Secure Boot: OEM Quirks (HP, Lenovo, Dell)

Disabling Secure Boot requires navigating to the laptop's UEFI/BIOS settings (usually pressing `F10`, `F2`, or `Del` at power-on).

### The HP 4-Digit PIN Trap
On HP laptops (e.g., HP 14s, Pavilion, ProBook), changing the Secure Boot setting triggers a security challenge on the subsequent boot:
1. The screen displays a black prompt with a randomly generated 4-digit numeric code (e.g., `0 4 2 9 + Enter`).
2. **Pitfall**: You MUST type the 4 digits and press `Enter`. Hitting `ESC` or ignoring the prompt cancels the change, and the BIOS silently reverts Secure Boot to enabled!
3. Once verified, boot into Linux and confirm `lockdown` is `[none]`.

---

## 3. MSR Userspace Write Permission (Linux Kernel >= 5.9)

Since Linux kernel 5.9, userspace writing to MSRs is locked down by default even for root, generating kernel warnings or `EPERM`.

To unlock MSR writes:
```bash
sudo modprobe msr
echo on | sudo tee /sys/module/msr/parameters/allow_writes
```

Ensure this is set during every boot sequence via systemd automation.
