# Systemd Persistence Engine

This directory contains systemd unit definitions designed to maintain hardware clock and power settings permanently across all power state transitions and overcome aggressive OEM Embedded Controller (EC) throttling.

---

## 🛡️ The Embedded Controller (EC) Reset Challenge

On laptops from HP, Lenovo, and Dell, the onboard Embedded Controller (EC) is programmed with factory firmware that monitors power supply states:
- When the AC charger is plugged in or disconnected, the EC fires an ACPI interrupt that silently resets CPU power limits back to 15W default.
- When resuming from **suspend**, **hybrid-sleep**, or **hibernate**, CPU MSR registers reset to factory hardware defaults (e.g. 2.4 GHz base).

---

## ⚙️ Units Description

| Unit File | Type | Role |
| :--- | :--- | :--- |
| **`linux-boost.service`** | Oneshot Service | Executes `/usr/local/bin/linux-hardware-tune.sh` on system boot, resume from suspend, and resume from hibernation. |
| **`linux-boost.timer`** | Monotonic Timer | Fires every **30 seconds** (`OnUnitActiveSec=30s`) to ensure that any EC-triggered power resets are immediately overridden back to peak performance. |

---

## 🚀 Manual Deployment

```bash
sudo cp systemd/linux-boost.service /etc/systemd/system/
sudo cp systemd/linux-boost.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now linux-boost.timer linux-boost.service
```

### Verification:
```bash
systemctl status linux-boost.timer
systemctl list-timers --all | grep linux-boost
```
