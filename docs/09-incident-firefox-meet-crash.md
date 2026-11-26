# 09 — Incident: Firefox force-close saat tutup screen share (Google Meet)

Status: **draft analisis — belum ada perubahan yang diterapkan**
Tanggal cek: 2026-11-26 (WIB)
Host: hpbadai — Athlon Gold 3150U (2C/4T), RAM 17.5 GiB, swap 8G zram (prio 100) + /swap.img 8G (prio 5), Wayland, Firefox 159.0 (snap)

---

## 1. Ringkasan

Firefox mati bukan karena OOM killer dan bukan karena RAM habis total.
Minidump membuktikan crash = **SIGSEGV (null deref) di jalur screencast PipeWire**, 3 kejadian,
alamat instruksi identik, semua di `meet.google.com`.

Tapi tuning-nya memang over di dua tempat, dan salah satunya bug nyata:

1. **BUG**: `/swap.img` di-`swapoff` + `swapon` ulang **setiap 30 detik** (traffic hari ini: 19 siklus dalam ~10 menit).
2. Prefs Firefox (2 GB cache RAM + 1 GB media cache + 16 content process + disk cache off) terlalu besar untuk 17.5 GiB / 4 thread.
3. Journald dibatasi 100 MB sehingga histori 1 minggu sudah hilang — investigasi "1 minggu terakhir" praktis mustahil.

---

## 2. Bukti yang dicek

| Cek | Hasil |
|---|---|
| `journalctl` kata kunci oom / oom-kill / Killed process | **tidak ada** (bukan OOM killer) |
| Minidump breakpad di `~/snap/firefox/common/.mozilla/firefox/Crash Reports/pending/` | 3 file, semuanya crash **main process** |
| Exception code | `EXCEPTION_SIGSEGV` (11), fault addr `0x18` → null pointer deref |
| RIP saat crash | `libxul.so+0x74cff46` — **identik di 3 crash** |
| Frame pointer crash thread | `firefox → libpipewire-0.3.so → libspa-support.so → libpipewire → libxul` (jalur capture screen) |
| URL saat crash | `meet.google.com/cmi-wriu-uqu`, `meet.google.com/meet/cmi-wriu-uq`, `meet.google.com/qmu-cbsz-fqb` |
| `user.js` dipasang | 2026-11-01 11:20 (commit `42090d8`) |
| Crash pertama | 2026-11-02 08:35 — **sehari setelah user.js dipasang** |
| Prefs aktif di `prefs.js` | `browser.cache.memory.capacity=2097152`, `media.memory_cache_max_size=1048576`, `dom.ipc.processCount=16`, `widget.dmabuf.wayland.enabled=true`, `media.hardware-video-decoding.force-enabled=true`, `gfx.webrender.all=true`, `browser.cache.disk.enable=false` |

Data memori tiap crash (dari file `.extra`):

| Waktu | Sesi | AvailablePhysical | AvailablePageFile | Uptime |
|---|---|---|---|---|
| 2026-11-02 08:35 | 11.4 menit | 8.2 GB | 2.9 GB | 11.4 mnt |
| 2026-11-24 09:45 | 4.6 jam | **345 MB** | **0 MB** | 279.7 mnt |
| 2026-11-25 08:38 | 11.6 menit | 9.4 GB | 10.0 GB | 11.6 mnt |

`AvailablePageFile = 0` pada crash 24 Nov artinya saat itu `/swap.img` sedang **nonaktif**
(atau sedang di-`swapoff`) — konsisten dengan bug butir 3 di bawah. Total page file normal 34.3 GB,
jadi 0 berarti swapfile memang dilepas.

---

## 3. Temuan

### A. Crash = bug Firefox di penutupan stream screencast PipeWire (bukan kehabisan RAM)

Bukti kuat:
- 2 dari 3 crash terjadi dengan RAM lega (8–9 GB available) → bukan memory exhaustion.
- RIP sama persis 3 kali, fault address `0x18` → deterministic null deref, bukan random corruption.
- Stack thread crash berisi `libpipewire` + `libspa-support` + `libdrm`/`libgallium` (Mesa) sebelum masuk `libxul`
  → kode Firefox yang menerima buffer screencast DMA-BUF, crash saat stream di-teardown (= saat tombol
  "Stop sharing" / tab share ditutup).

Ini **tidak bisa dibuktikan 100%** sebagai bug murni Firefox karena tidak ada simbol; kesimpulan ini
dari pola (RIP identik + stack pipewire + timing penutupan share). Yang bisa dipastikan: lokasi crash
ada di jalur capture, bukan di allocator.

Prefs yang menaikkan peluang masuk jalur ini: `widget.dmabuf.wayland.enabled=true`,
`media.hardware-video-decoding.force-enabled=true`, `gfx.webrender.all=true` (Wayland + Mesa 25.2.8 + Vega 3).
Vega 3 (Raven2, device `0x15d8`) punya VCN terbatas; memaksa dmabuf + hw decode menambah jalur yang belum stabil.

### B. BUG: `/swap.img` di-toggle setiap 30 detik

File: `/home/uyasky/.local/bin/ryzen-permanent-boost.sh` baris 75–78

```bash
if swapon --show | grep "/swap.img" | grep -qv " 5 "; then
    swapoff /swap.img >/dev/null 2>&1
    swapon -p 5 /swap.img >/dev/null 2>&1
fi
```

Kenapa selalu true: kolom PRIO adalah kolom terakhir, jadi baris tercetak
`/swap.img  file  8G  0B  5` — **tanpa spasi setelah angka 5**. Pola `" 5 "` tidak pernah match,
`grep -qv` selalu sukses → `swapoff` + `swapon` dijalankan terus.

Diperparah oleh `ryzen-boost.timer` (`OnUnitActiveSec=30s`) yang menjalankan script itu sebagai root
tiap 30 detik. Bukti kernel log hari ini:

```
Nov 26 22:35:56 Adding 8388604k swap on /swap.img.  Priority:5 ...
Nov 26 22:36:31 Adding 8388604k swap on /swap.img.  Priority:5 ...
Nov 26 22:37:06 Adding 8388604k swap on /swap.img.  Priority:5 ...
```

19 siklus dalam ~10 menit. Efeknya:
- setiap `swapoff` memaksa semua halaman yang ada di swap kembali ke RAM → spike pressure + I/O,
  dan bisa berjalan puluhan detik kalau swap sedang terpakai (saat Meet + banyak tab);
- selama jendela itu `AvailablePageFile = 0` (persis kondisi crash 24 Nov);
- tulis/baca swapfile 8 GB berulang di SSD = write wear sia-sia;
- `zram` jadi tidak berguna karena tiering-nya direset terus.

Script yang sama juga menulis ulang `/etc/sysctl.d/99-performance.conf` **setiap 30 detik**
(disk write rutin tanpa manfaat) dan melakukan MSR write `amdctl` + `ryzenadj` tiap 30 detik.

Catatan: `scripts/setup-zram.sh` di repo **tidak** punya bug ini (pakai `awk`, cek idempoten benar).
Bug hanya ada di script live di `~/.local/bin`.

### C. Prefs Firefox over-budget untuk hardware ini

`scripts/setup-firefox-ram.sh` mengasumsikan "20 GB RAM Edition", realitanya 17.5 GiB / 4 thread:

| Pref | Nilai sekarang | Masalah |
|---|---|---|
| `browser.cache.disk.enable` | `false` | semua objek jatuh ke RAM cache, tidak ada spill ke disk |
| `browser.cache.memory.capacity` | `2097152` KB = **2 GB** | 2 GB per profile, di atas kebutuhan normal; menahan memori sampai tekanan tinggi |
| `media.memory_cache_max_size` | `1048576` KB = **1 GB** | buffer media besar, dipakai juga saat Meet decode/encode |
| `dom.ipc.processCount` | `16` | 16 content process di CPU 2C/4T → overhead + fragmentasi memori |
| `browser.tabs.unloadOnLowMemory` | `false` | tab tidak pernah dilepas saat memori sempit |
| `browser.sessionhistory.max_total_viewers` | `20` | pref ini **sudah tidak dipakai** Firefox modern (bfcache pakai `browser.sessionhistory.max_total_viewers` tidak lagi); klaim "20 page pre-rendered" di komentar script tidak akurat |

Kombinasi ini tidak menyebabkan SIGSEGV, tapi:
- memperbesar memori yang harus di-reclaim tiap kali `swapoff` jalan (butir B),
- membuat crash 24 Nov mendarat di kondisi 345 MB free.

### D. Journald 100 MB menghapus histori

`SystemMaxUse=100M` + `SystemMaxFileSize=25M` membuat log boot 24–25 Nov hilang di tengah investigasi ini
(`journalctl --list-boots` hanya menyisakan 5 boot, kernel log boot lama sudah tidak ada).
Untuk mesin tuning, 100 MB terlalu kecil — tidak cukup untuk membuktikan/menyangkal regresi.

### E. Duplikasi `user.js`

`setup-firefox-ram.sh` memakai `echo >> user.js`, jadi tiap kali dijalankan blok prefs ditambahkan lagi.
Tidak merusak (prefs terakhir menang), tapi membuat file tidak bisa dibaca/di-diff.

---

## 4. Rekomendasi (belum diterapkan)

### P0 — stop kerusakan yang sedang berjalan

1. Matikan timer 30 detik, sisakan hook boot/suspend saja:

```bash
sudo systemctl disable --now ryzen-boost.timer
```

2. Perbaiki logika swap di `/home/uyasky/.local/bin/ryzen-permanent-boost.sh` — ganti baris 75–78:

```bash
# Demote /swap.img ke fallback prio 5, hanya kalau memang belum 5 (idempoten)
current_prio=$(swapon --show=PRIO,NAME --noheadings | awk '$2=="/swap.img"{print $1}')
if [ -n "$current_prio" ] && [ "$current_prio" != "5" ]; then
    swapoff /swap.img >/dev/null 2>&1
    swapon -p 5 /swap.img >/dev/null 2>&1
fi
```

   Lebih baik lagi: pindahkan seluruh blok swap + sysctl keluar dari script periodik, jalankan sekali saat boot.
   `swapoff` yang tidak perlu tidak pernah aman di mesin yang sedang dipakai meeting.

3. Verifikasi setelah fix (tunggu 2 menit, harus 0 baris):

```bash
journalctl -k --since '-2 min' | grep -c 'Adding 8388604k swap'
```

### P1 — turunkan prefs Firefox ke level aman

Ubah `scripts/setup-firefox-ram.sh` (lalu jalankan ulang untuk menimpa `user.js`, dan hapus pref lama di `prefs.js`):

```javascript
// cache: pakai disk cache kecil + RAM cache moderat (bukan 2 GB)
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 262144);      // 256 MB
user_pref("browser.cache.memory.capacity", 524288);    // 512 MB (bukan 2 GB)
user_pref("browser.cache.memory.max_entry_size", 51200);
user_pref("media.memory_cache_max_size", 262144);      // 256 MB (bukan 1 GB)

// biarkan Firefox yang mengelola tab/bfcache
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("dom.ipc.processCount", 8);                  // 4 thread, jangan 16

// hapus yang berisiko di Wayland + Vega 3
// user_pref("widget.dmabuf.wayland.enabled", true);          <- dibuang
// user_pref("media.hardware-video-decoding.force-enabled", true); <- dibuang
// user_pref("gfx.webrender.all", true);                      <- dibuang (default sudah WebRender)
user_pref("media.ffmpeg.vaapi.enabled", true);          // tetap, ini aman & berguna
```

Uji A/B wajib: satu meeting Meet dengan share screen + stop share.

### P2 — observability supaya insiden berikutnya bisa dibuktikan

- Naikkan `SystemMaxUse` jadi 512M–1G di `configs/journald-size.conf` (write wear journal tidak sebesar
  churn swap 8 GB tiap 30 detik).
- Pertimbangkan `vm.dirty_ratio=20` / `dirty_background_ratio=10` diturunkan (mis. 10/5): 20% dari 17.5 GiB
  = 3.5 GB dirty page sekaligus → stall I/O panjang saat writeback, terasa saat meeting + compile.
- `vm.vfs_cache_pressure=10` aman untuk desktop, tapi tidak ada hubungannya dengan kasus ini.
- Tambahkan ke docs: cara baca minidump Firefox (breakpad) supaya next time tidak perlu nebak.

---

## 5. Rencana verifikasi

1. Setelah P0: pastikan tidak ada lagi `Adding ... swap` periodik dan `swapon --show` stabil (prio 100 & 5, USED tidak loncat).
2. Setelah P1: buka Meet, share screen 10 menit, stop share, cek:
   - `ls ~/snap/firefox/common/.mozilla/firefox/Crash\ Reports/pending/` tidak bertambah,
   - `journalctl -k | grep -i segfault` bersih,
   - `about:memory` / `about:processes` menunjukkan total RSS turun dibanding sebelumnya.
3. Kalau masih crash dengan prefs minimal → berarti murni bug Firefox: workaround berikutnya
   pakai Chrome untuk Meet, atau jalankan Firefox XWayland (`MOZ_ENABLE_WAYLAND=0`) untuk mematikan jalur dmabuf.
4. Rollback: `user.js` bisa dihapus per profile, sysctl dari `configs/99-performance.conf`, `scripts/uninstall.sh`.

---

## 6. Kausalitas: tuning, suhu, atau bug Firefox?

Pertanyaan: "ini gara-gara tuning nggak?" Jawaban berlapis, dipisah per tingkat keyakinan.

| Dugaan | Bukti | Status |
|---|---|---|
| RAM habis → OOM killer bunuh Firefox | Tidak ada `oom-kill` di kernel log; 2 dari 3 crash punya 8–9 GB RAM kosong | **Terbantah** |
| Panas CPU menyebabkan Firefox SIGSEGV | Tidak ada log thermal throttle / MCE / hardware error; gejala panas = clock turun / lambat / mati total, bukan satu aplikasi SIGSEGV di alamat yang sama 3x | **Tidak didukung bukti** |
| Bug Firefox di jalur screencast PipeWire | RIP `libxul.so+0x74cff46` identik 3x, fault `0x18`, stack pipewire+spa+drm, semua di Meet | **Paling kuat** |
| Tuning memunculkan bug itu | Jalur dmabuf/VA-API dipaksa via user.js; crash pertama 1 hari setelah user.js dipasang | **Kuat, perlu A/B** |
| Bug swap 30s memperparah | 19 siklus/10 menit; `AvailablePageFile=0` saat crash 24 Nov | **Terkonfirmasi sebagai bug terpisah** |

Soal suhu — data sekarang:

```
Tctl 70.2°C, edge GPU 70.0°C   (idle, load average 0.28)
scaling_min_freq = scaling_max_freq = 2400000   (CPU dikunci 2.4 GHz)
scaling_cur_freq = ~1.88 GHz                    (di bawah batas minimum!)
boost = 1, driver = acpi-cpufreq, amd_pstate = tidak ada
```

Tiga hal yang perlu dicatat:

1. 70 °C saat idle itu panas. Efeknya performa (throttle), bukan crash per-aplikasi.
2. Clock dilaporkan 1.88 GHz padahal min = max = 2.4 GHz. Ini tidak konsisten dan menandakan
   override P-state lewat MSR (`amdctl` di `ryzen-permanent-boost.sh`) bertabrakan dengan `acpi-cpufreq`.
   Override MSR seperti ini **memang bisa** menyebabkan SIGSEGV acak — tapi kalau itu penyebabnya,
   alamat crash tiap aplikasi akan berbeda-beda dan acak, bukan satu offset identik 3x.
3. Crash aplikasi lain dalam sepekan (`PanGPA` SIGSEGV libc, `gnome-terminal` SIGTRAP, WPS, Xwayland)
   mayoritas punya penyebab sendiri-sendiri dan bukan bukti kuat ketidakstabilan hardware.
   Kalau setelah tuning dimatikan crash acak antar-aplikasi masih muncul, baru curigai RAM/clock.

Kesimpulan: crash Meet **bukan** karena RAM habis dan **bukan** karena panas. Penyebab langsungnya bug
Firefox di jalur PipeWire screencast; tuning yang dipasang 1 Nov menyalakan jalur itu dan bug swap 30 detik
menambah tekanan memori pada saat yang sama. Panas menjelaskan laptop terasa berat/lambat, bukan force-close.

### Matriks uji untuk membuktikan

| Uji | Cara | Kalau hasilnya |
|---|---|---|
| A. Prefs minimal | Terapkan P1, restart Firefox, satu Meet + share screen + stop share | Tidak crash → prefs tuning penyebab exposure |
| B. Tanpa Wayland | `MOZ_ENABLE_WAYLAND=0 firefox`, ulangi uji A | Tidak crash → jalur dmabuf Wayland yang salah |
| C. Tanpa override clock | `systemctl disable --now ryzen-boost.timer`, reboot, ulangi | Crash acak hilang → amdctl/ryzenadj sumbernya |
| D. Panas | `watch -n2 sensors` selama Meet | Frekuensi drop / >95 °C → batasi TDP, bukan penyebab crash |
| E. RAM | `memtest86+` 2 pass semalam | Ada error → hardware, semua analisis di atas batal |

---

## 7. Status implementasi (2026-11-26, setelah approval)

Sudah diterapkan dan diverifikasi:

| Item | Lokasi | Verifikasi |
|---|---|---|
| Perbaikan logika demote swap (idempoten, tidak `swapoff` terus) | `~/.local/bin/ryzen-permanent-boost.sh` | `bash -n` OK; `current_prio` sekarang 5 → blok tidak jalan |
| Stop swap churn | efek dari fix di atas, timer 30s tetap jalan | `journalctl -k --since '-2 min' \| grep -c 'Adding 8388604k swap'` → **0** (sebelumnya ~35 detik sekali) |
| Tulis sysctl hanya kalau isinya beda | script yang sama | tidak ada write disk tiap 30 detik |
| `dirty_ratio` 20→10, `dirty_background_ratio` 10→5 | runtime + `/etc/sysctl.d/99-performance.conf` + repo | `sysctl vm.dirty_ratio` → 10, `vm.dirty_background_ratio` → 5 |
| Prefs Firefox aman + idempoten | `scripts/setup-firefox-ram.sh` (repo) dan `user.js` 6 profile live | script dijalankan 2x, blok tidak dobel, prefs custom di luar blok tetap ada |
| Cache RAM 2 GB→512 MB, media 1 GB→256 MB, disk cache hidup 256 MB, proses 16→8 | `user.js` semua profile | perlu restart Firefox untuk berlaku |
| `widget.dmabuf.wayland.enabled=false`, `hardware-video-decoding.force-enabled=false` | `user.js` semua profile | perlu restart Firefox untuk berlaku |
| Dokumentasi diselaraskan | `docs/04`, `docs/05`, `configs/*`, `ARCHITECTURE.md`, `README.md` | grep nilai lama → bersih |

Masih perlu sudo (belum dijalankan, menunggu password):

```bash
# 1. Matikan hanya timer periodiknya; service tetap ada untuk hook boot/suspend.
sudo systemctl disable --now ryzen-boost.timer

# 2. Naikkan journald ke 512 MB supaya insiden berikutnya masih bisa dibuktikan.
sudo install -m 644 configs/journald-size.conf /etc/systemd/journald.conf.d/00-limit-size.conf
sudo systemctl restart systemd-journald

# 3. Pasang ulang sysctl yang sudah diperbaiki (opsional, runtime-nya sudah ter-set).
sudo install -m 644 configs/99-performance.conf /etc/sysctl.d/99-performance.conf
sudo sysctl --system
```

Sisa pekerjaan yang butuh keputusan, bukan sudo:

- Clock CPU terkunci `min = max = 2400 MHz` sementara `scaling_cur_freq` terbaca 1.59–1.88 GHz
  (setelah fix: 1.596 GHz, suhu turun 70 °C → 49 °C idle). Artinya permintaan `acpi-cpufreq` dan
  tabel P-state hasil `amdctl` tidak sinkron → CPU bisa berjalan **di bawah** clock stock sambil tetap
  terkunci tanpa boost. Ini sumber panas + potensi instabilitas acak. Opsi: buang blok `amdctl` dari
  script, biarkan `acpi-cpufreq`/`amd_pstate` normal, atau turunkan `ryzenadj --stapm-limit` ke 15 W.
- `systemd/linux-boost.timer` di repo sudah diubah dari `OnUnitActiveSec=30s` menjadi `1h`
  (re-apply MSR tiap 30 detik tidak ada manfaat terukur, hanya nambah panas dan risiko).
- Uji A/B setelah restart Firefox: satu Meet + share screen + stop share, lalu cek
  `~/snap/firefox/common/.mozilla/firefox/Crash Reports/pending/` tidak bertambah.

---

## 9. Suhu & power: 90 °C saat charging (2026-11-26)

Data saat diperiksa (AC tersambung, battery `Charging`, load avg 1.79):

```
Tctl 72 °C / GPU edge 72 °C   (idle-ish, modem hermes + gnome-shell)
cpu0..3 cur = 2.34-2.37 GHz, min = max = 2400000, governor = performance
scaling_available_frequencies = 2400000 1700000 1400000
scaling_available_governors   = conservative ondemand userspace powersave performance schedutil
cpuinfo_max_freq = 2400000   (firmware HP tidak mengekspos 3.3 GHz)
ACPI thermal trip points invalid ("No valid trip points") -> tidak ada throttle ACPI
```

Penyebab 90 °C: konfigurasi yang sengaja dibuat "selalu kencang" di atas hardware 15 W.

1. `scaling_min_freq = 2400000` + governor `performance` → CPU tidak pernah turun, idle pun 2.4 GHz.
2. `ryzenadj --stapm-limit=20000 --fast-limit=24000 --max-performance` → di atas TDP stock 15 W,
   heatsink HP 14" tidak sanggup membuang panas itu.
3. Override MSR `amdctl` P0=3.3 GHz tidak pernah tercapai (firmware max 2.4 GHz) tapi tetap menulis MSR
   tiap 30 detik → bikin pembacaan clock tidak sinkron (1.59–1.88 GHz padahal min = max).
4. Charging menambah panas VRM + baterai (~5–10 W disipasi internal). Kombinasi 1+2+4 = 90 °C.

Efek: thermal throttle (performa jatuh tidak konsisten), fan berisik, baterai cepat tua,
dan risiko instabilitas acak. Bukan penyebab crash Firefox (lihat bagian 6), tapi perlu dibereskan.

Sudah diubah (script, berlaku saat dijalankan / boot berikutnya):

- blok `amdctl` dihapus dari `amd-tune-hardware.sh` (repo) dan `~/.local/bin/ryzen-permanent-boost.sh`
- governor `performance` → `schedutil`, `scaling_min_freq` → P-state terendah yang tersedia (1.4 GHz)
- `ryzenadj` 20/24/20 W + `--max-performance` → 15/20/15 W, `--tctl-temp=85`

Cara mengukur hasil setelah diterapkan:

```bash
# 1. Terapkan runtime (butuh root)
sudo /home/uyasky/.local/bin/ryzen-permanent-boost.sh

# 2. Cek governor dan frekuensi sudah turun saat idle
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
sensors | grep -E 'Tctl|edge'

# 3. Uji beban 60 detik, lihat suhu puncak
for i in 1 2 3 4; do yes > /dev/null & done; sleep 60; kill %1 %2 %3 %4
sensors | grep Tctl
```

Target realistis: idle 45–55 °C, beban penuh 75–85 °C saat charging. Kalau masih >85 °C,
turunkan `--stapm-limit` ke 12000 dan `--fast-limit` ke 15000.

### Hasil pengukuran setelah perubahan (2026-11-26 23:18–23:20, AC + charging)

```
sebelum : idle 72 °C, semua core dipaku 2.34-2.37 GHz (min=max=2.4 GHz, governor performance)
sesudah : idle 52.2 °C, core turun ke ~1.01 GHz
beban   : 4 core `yes` 45 detik -> puncak 85.2 °C (charging), core 1.2-2.2 GHz
```

Idle turun 20 °C, dan CPU akhirnya bisa downclock (2.4 GHz -> 1.0 GHz). Puncak sintetis 85 °C masih
di batas target; beban nyata (Meet, browser) jauh di bawah itu karena hanya 1-2 thread.

Verifikasi limit SMU setelah `sudo /home/uyasky/.local/bin/ryzenadj -i`:

```
STAPM LIMIT      15.000 W      PPT LIMIT FAST   20.000 W
PPT LIMIT SLOW   15.000 W      THM LIMIT CORE   85.000 C
STAPM VALUE       7.856 W      PPT VALUE FAST    8.114 W   (idle, sudah turun)
```

Catatan: `ryzenadj` melaporkan `no compatible ryzen_smu kernel module found, fallback to /dev/mem`.
Akses lewat `/dev/mem` tetap bekerja tapi kurang aman/rapi; modul `ryzen_smu` (DKMS) bisa dipasang
kalau mau jalur resmi. Bukan blocker.

## 10. Hasil uji A/B (2026-11-26 23:43–23:45) — LULUS

Meet + share screen dijalankan dengan konfigurasi baru:

```
23:43:16  portal screencast aktif (share screen)
23:44:58  Tctl 85.8 °C, edge 85 °C  -> ditahan di THM 85 (bukan naik ke 95-100)
          load 6.35, cpu0/1 895 MHz, cpu2/3 2.02 GHz (throttle sesuai batas)
          mem available 10.8 GB, swap 0 B, PSI memory 0.00
          firefox RSS total 1.18 GB
23:45:xx  stop share -> tidak ada crash
```

Verifikasi setelah stop share: `Crash Reports/pending` tetap 3 file lama, tidak ada `segfault`/OOM/MCE
di kernel log, Firefox masih jalan. Sebelum fix, pola ini konsisten bikin SIGSEGV di
`libxul.so+0x74cff46`. Jadi hipotesis "prefs dmabuf/force-hwdecode + mem pressure yang memunculkan
crash" lolos uji pertama.

## 11. Temuan tambahan: driver WiFi rtw88 power save (bukan penyebab crash Firefox)

Saat Meet berjalan, kernel log dipenuhi:

```
rtw88_8821ce 0000:03:00.0: firmware failed to leave lps state   (664 kali hari ini)
rtw88_8821ce 0000:03:00.0: failed to send h2c command
WARNING: drivers/net/wireless/realtek/rtw88/ps.c:105 at rtw_power_mode_change
         Workqueue: phy0 rtw_watch_dog_work
```

Ini bug power-save firmware RTL8821CE saat masuk deep LPS. Bukan penyebab crash Firefox, tapi bisa
bikin WiFi drop/lag di tengah meeting. Kondisi sekarang: `/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf`
= `wifi.powersave = 3` (aktif), `disable_lps_deep = N`.

Perbaikan yang disarankan (pilih satu, keduanya butuh root):

```bash
# Opsi A: matikan deep LPS di driver (targeted, tetap hemat daya)
sudo install -m 644 configs/rtw88-deep-lps.conf /etc/modprobe.d/rtw88-deep-lps.conf
# lalu reboot (atau unload/reload modul wifi saat tidak sedang meeting)

# Opsi B: matikan WiFi powersave lewat NetworkManager
printf '[connection]\nwifi.powersave = 2\n' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl reload NetworkManager
```

### Bukti dampak: jitter per interface (2026-11-27 00:15, kedua interface aktif)

```
eno1  (r8169, 100Mbps/Full) -> gateway 192.168.100.1: 0% loss, avg 0.448 ms, max 0.711, mdev 0.055
                                1.1.1.1               : 0% loss, avg 18.47 ms, mdev 0.153
wlp3s0 (rtw88_8821ce)       -> gateway 192.168.100.1: 0% loss, avg 27.872 ms, max 149.676, mdev 51.781
                                1.1.1.1               : 0% loss, avg 34.91 ms, mdev 17.883
```

WiFi tidak kehilangan paket, tapi latensinya 60x LAN dan spike-nya sampai 150 ms — inilah yang terasa
"putus-putus" di Meet walaupun sinyal -40 dBm (kuat). Riwatat disconnect 2 hari: `reason=4`
(inactivity) 91x, `reason=3` 19x, `reason=15` 2x, `reason=7` 1x.

### Catatan dual-homing

Saat ini `eno1` dan `wlp3s0` sama-sama UP di subnet yang sama (`192.168.100.14` dan `.18`), dua default
route dengan metric 100 dan 600. Kombinasi interface WiFi berjitter + dua jalur ke gateway yang sama
membuat trafik bisa pindah jalur tanpa terasa, dan ARP bisa keluar dari interface yang salah.
Kalau kabel LAN terpasang, matikan WiFi:

```bash
nmcli radio wifi off                       # sesi ini saja
nmcli connection modify "<nama-wifi>" connection.autoconnect no   # permanen
```

### Catatan LAN 100 Mbps

`r8169 ... Link is Up - 100Mbps/Full` padahal RTL8168h mendukung 1000 Mbps. Biasanya kabel (butuh
minimal CAT5e 4-pair) atau port switch. Tidak menyebabkan drop (0 carrier lost, 0% loss), tapi kalau
ingin 1 Gbps cek kabelnya. 100 Mbps tetap cukup untuk Meet 1080p.

## 12. Yang belum terbukti

- Pref mana yang persis memicu crash (RIP identik 3x tapi tanpa simbol). Uji A/B P1 yang akan menjawab.
- Apakah crash 24 Nov juga dipicu swap-churn atau murni bug yang sama; RIP-nya identik, jadi kemungkinan
  besar jalur yang sama, dengan memory pressure sebagai pemicu tambahan.
- Apakah ada crash lain dalam 1 minggu terakhir yang tidak terekam: journald 100 MB sudah memotong log,
  dan crash report lama sudah tidak di `pending/` (kemungkinan sudah terkirim/terhapus).
