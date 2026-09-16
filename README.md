# windows-proxy-pool

Sistem **30 local HTTP proxy server** untuk Windows 10/11, berjalan native
(tanpa WSL, Docker, Termux, atau Linux VM). Setiap instance adalah proses
`3proxy.exe` terpisah yang listen hanya di `127.0.0.1`, dengan Basic Auth
yang berbeda-beda.

```
127.0.0.1:8001  ->  proxy1:pass1
127.0.0.1:8002  ->  proxy2:pass2
...
127.0.0.1:8030  ->  proxy30:pass30
```

---

## ⚠️ PENTING: 30 proxy lokal TIDAK berarti 30 IP publik berbeda

**30 instance proxy lokal tidak menghasilkan 30 IP publik yang berbeda.**

Tanpa upstream proxy, VPN, atau network interface yang berbeda, seluruh
instance akan tetap keluar (egress) menggunakan **IP publik Windows yang
sama**. Konfigurasi default di project ini **tidak menggunakan upstream
proxy** — jadi semua port 8001–8030 akan menampilkan IP publik yang identik
saat di-test (lihat `test.ps1`).

Jangan mengklaim bahwa setiap port menghasilkan IP publik yang berbeda.
Jika Anda memang membutuhkan IP publik yang berbeda, Anda harus menambahkan
upstream proxy/VPN/interface jaringan yang berbeda untuk tiap instance —
itu di luar cakupan project ini, dan `config/*.conf` bisa diedit / di-extend
untuk itu (misalnya menambah direktif `parent`).

---

## Kenapa 3proxy?

| Kebutuhan | Kenapa 3proxy cocok |
| --- | --- |
| Native Windows, tanpa WSL/Docker/VM | Satu file `3proxy.exe` kecil yang berjalan langsung di Windows |
| 30 instance sebagai proses terpisah | Satu config file per instance, dijalankan sebagai proses `3proxy.exe` terpisah |
| Basic Auth berbeda per instance | Direktif `auth strong` + file `users` per instance |
| Logging terpisah per instance | Direktif `log` per config -> `logs/proxyXX.log` |
| Management proses | Direktif `pidfile` -> file PID di `run/` |
| Tanpa upstream proxy (default) | Tanpa direktif `parent`, 3proxy konek langsung ke internet |

Alternatif yang dipertimbangkan dan kenapa tidak dipakai: **Squid**
(setup Windows berat dan ribet), **Privoxy** (build Windows sudah usang),
**mitmproxy** (butuh runtime Python, berat untuk 30 instance), **Xray/v2ray**
(overkill untuk HTTP proxy sederhana).

3proxy versi **0.9.8** (rilis Agustus 2026, aktif dikembangkan).

---

## Struktur Project

```
windows-proxy-pool/
├── bin/                  # 3proxy.exe + DLL pendamping (hasil install.ps1)
├── config/               # config per instance (hasil generate.ps1)
│   ├── proxy01.conf      #   -> 127.0.0.1:8001, user proxy1
│   ├── proxy01.users     #   -> kredensial proxy1:pass1 (dilindungi ACL)
│   └── ... proxy30.conf / proxy30.users
├── logs/                 # log per instance: proxy01.log ... proxy30.log
├── run/                  # file PID per instance: proxy01.pid ... proxy30.pid
├── scripts/
│   ├── install.ps1       # unduh & pasang binary 3proxy
│   ├── generate.ps1      # generate config + users dari credentials.txt
│   ├── start.ps1         # start semua proxy (proses terpisah) + auto-export list
│   ├── stop.ps1          # stop semua proxy
│   ├── restart.ps1       # stop lalu start + auto-export list
│   ├── status.ps1        # status proses + port tiap instance
│   ├── test.ps1          # test otomatis semua proxy (tabel)
│   ├── export-proxies.ps1# export proxy-list.txt dari proxy yang RUNNING
│   ├── run.ps1           # jalankan semuanya: start -> tunggu port -> health check -> export
│   └── menu.ps1          # menu interaktif (tetap terbuka)
├── shortcuts/            # shortcut Windows (.lnk): Start/Stop/Restart/Status/Test/Pool
├── credentials.txt       # user:pass per instance (dibuat generate.ps1, jangan di-commit)
├── proxy-list.txt        # hasil export: http://user:pass@127.0.0.1:port (BERISI KREDENSIAL!)
├── SPEC.md               # spesifikasi asli project ini
└── README.md
```

---

## Persyaratan

- Windows 10/11
- PowerShell 5.1+ (bawaan Windows)
- `curl.exe` (bawaan Windows 10/11)
- Koneksi internet saat menjalankan `install.ps1` (unduh 3proxy) dan saat
  `test.ps1` (cek IP publik)

---

## Cara Pakai (Quick Start)

Buka **PowerShell** di folder project, lalu jalankan (ExecutionPolicy
di-bypass per perintah):

```powershell
# 1. Install dependency (unduh 3proxy.exe ke bin\)
powershell -ExecutionPolicy Bypass -File scripts\install.ps1

# 2. Generate konfigurasi 30 proxy (config\*.conf, config\*.users, credentials.txt)
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1

# 3. JALANKAN SEMUANYA: start 30 proxy, tunggu port, health check, export proxy-list.txt
powershell -ExecutionPolicy Bypass -File scripts\run.ps1

# Alternatif langkah manual:
powershell -ExecutionPolicy Bypass -File scripts\start.ps1      # start saja (otomatis export list)
powershell -ExecutionPolicy Bypass -File scripts\test.ps1        # test semua proxy
powershell -ExecutionPolicy Bypass -File scripts\status.ps1      # status proses & port
```

Atau, dari PowerShell biasa (bukan `cmd`):

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1
.\scripts\generate.ps1
.\scripts\start.ps1
.\scripts\test.ps1
```

---

## Referensi Script

| Script | Fungsi |
| --- | --- |
| `install.ps1` | Mengunduh binary 3proxy (GitHub releases), mengekstrak ke `bin\`, membuat folder `config\`, `logs\`, `run\`. Deteksi arsitektur otomatis (x64/x86/arm64). |
| `generate.ps1` | Membaca `credentials.txt`, membuat `config\proxyXX.conf` + `config\proxyXX.users`, lalu membatasi permission file kredensial via `icacls`. Jika `credentials.txt` belum ada, dibuat pola default `proxy1:pass1`..`proxy30:pass30`. |
| `start.ps1` | Menjalankan 1 proses `3proxy.exe` per instance (30 proses terpisah), menunggu PID file, melewati instance yang sudah berjalan. |
| `stop.ps1` | Menghentikan semua proses via PID file (`run\`), dengan fallback pencocokan command-line. Menghapus PID file yang basi. |
| `restart.ps1` | `stop.ps1` lalu `start.ps1` + refresh `proxy-list.txt`. |
| `status.ps1` | Tabel per instance: Port, PID, status proses, dan apakah port benar-benar listening di `127.0.0.1`. |
| `test.ps1` | Test otomatis tiap proxy: (1) request **tanpa** kredensial harus ditolak `407` (Auth aktif), (2) request **dengan** kredensial harus sukses dan mengembalikan IP publik. Output tabel `Proxy | Port | Auth | Status | Public IP`. |
| `export-proxies.ps1` | Membaca `credentials.txt` + config tiap instance, hanya memasukkan proxy yang **RUNNING & listening**, lalu menulis `proxy-list.txt` (format `http://user:pass@127.0.0.1:port`). Validasi format + dedupe, overwrite tiap run. |
| `run.ps1` | **Run everything**: cek 3proxy -> start semua -> tunggu port 8001–8030 listening -> health check (BasicAuth + egress) -> export list -> ringkasan `Running/Listening/Healthy`. |
| `menu.ps1` | Menu interaktif (Start/Stop/Restart/Status/Test/Export/Exit). Tetap terbuka setelah tiap operasi. |

---

## Mode Produksi / Ketahanan

Fitur tambahan untuk pemakaian jangka panjang: rotasi kredensial, auto-start
saat boot, monitoring + auto-restart, dan rotasi/pembersihan log.

### 1. Rotasi kredensial (password acak)

Password default `pass1`..`pass30` mudah ditebak. Untuk produksi, rotasikan ke
password acak 16 karakter (hanya alfanumerik aman untuk URL):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\rotate-credentials.ps1
```

Script ini: stop seluruh pool -> generate `credentials.txt` baru (password
acak) + tulis ulang `config\*.conf` / `config\*.users` -> start ulang -> test
30/30. File `proxy-list.txt` lama dihapus agar tidak ada daftar dengan
kredensial basi.

Opsional: `-PassLength 24` untuk password lebih panjang, `-SkipTest` untuk
rotasi cepat. Satu kali saja via `generate.ps1 -RandomPass` juga bisa.

> Password acak hanya memakai charset aman `A-Za-z0-9` (tanpa `:` `@` `/`
> spasi) sehingga tetap valid di URL proxy dan di `export-proxies.ps1`.

### 2. Auto-start saat boot / logon

Agar pool otomatis hidup setelah Windows restart:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1
```

Mendaftarkan Scheduled Task `windows-proxy-pool` yang menjalankan `start.ps1`
pada logon user. Idempoten: jika pool sudah jalan, `start.ps1` melewatinya.
Hapus dengan `-Remove`.

### 3. Monitoring + auto-restart

Jalankan sekali sebagai task terjadwal (default tiap 5 menit):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-monitor.ps1
```

Mendaftarkan Scheduled Task `windows-proxy-pool-monitor` yang memanggil
`monitor.ps1 -AutoRestart -Silent`. Monitor memeriksa tiap instance
(port listening + proses hidup + BasicAuth + egress), otomatis me-restart
instance yang gagal (hingga 3x percobaan), dan menulis:

| Output | Isi |
| --- | --- |
| `run\pool-status.json` | Status terstruktur (healthy/unhealthy/critical + instance list) |
| `run\pool-status.log` | Baris ringkasan per run (append) + event restart |
| Windows Event Log | Sumber `windows-proxy-pool`, warning/error otomatis |

Jalankan manual kapan saja: `scripts\monitor.ps1` (tanpa `-AutoRestart` = hanya
monitor, tidak me-restart). Hapus task dengan `install-monitor.ps1 -Remove`.

### 4. Rotasi & pembersihan log

Konfigurasi yang dihasilkan `generate.ps1` kini memakai rotasi log 3proxy
(**harian** secara default; atur dengan `-LogRotation D|H|W|M|Y`, kosongkan
untuk satu file stabil). File log lama dirapikan dengan:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\cleanup-logs.ps1          # simpan 30 hari
powershell -ExecutionPolicy Bypass -File scripts\cleanup-logs.ps1 -RetentionDays 7
```

Menghapus file log ter-rotasi yang lebih tua dari `-RetentionDays` (default 30)
atau lebih besar dari `-MaxLogSizeMB` (default 200 MB), plus PID file basi.
Bisa dijadwalkan harian via Task Scheduler.

---

## Proxy List Otomatis (`proxy-list.txt`)

`export-proxies.ps1` (dijalankan otomatis oleh `start.ps1`, `restart.ps1`, dan `run.ps1`)
menghasilkan `proxy-list.txt` berisi satu baris per proxy yang sedang berjalan:

```
http://proxy1:pass1@127.0.0.1:8001
http://proxy2:pass2@127.0.0.1:8002
...
http://proxy30:pass30@127.0.0.1:8030
```

Baris ke-`i` memakai kredensial baris ke-`i` dari `credentials.txt` dan port
aktual dari `config\proxyNN.conf`. Proxy yang tidak RUNNING/listening tidak
dimasukkan.

> ⚠️ **PENTING (Keamanan):** `proxy-list.txt` berisi **kredensial plaintext**
> (`user:pass`). Jangan bagikan file ini, jangan upload ke internet, dan jangan
> commit ke Git. File ini sudah masuk `.gitignore`. Hapus file ini jika tidak
> diperlukan, atau buat ulang kapan saja dengan
> `powershell -ExecutionPolicy Bypass -File scripts\export-proxies.ps1`.

## Shortcut Windows

Semua shortcut tersedia di `shortcuts\` (dan sebagian juga di Desktop):

| Shortcut | Menjalankan |
| --- | --- |
| `FAi Proxy Pool.lnk` | `scripts\menu.ps1` (menu interaktif) |
| `FAi Proxy - Start.lnk` | `scripts\run.ps1` (start + health check + export) |
| `FAi Proxy - Stop.lnk` | `scripts\stop.ps1` |
| `FAi Proxy - Restart.lnk` | `scripts\restart.ps1` |
| `FAi Proxy - Status.lnk` | `scripts\status.ps1` |
| `FAi Proxy - Test.lnk` | `scripts\test.ps1` |

Double-klik shortcut untuk menjalankan; working directory otomatis
`C:\fai\proxy`. `FAi Proxy Pool.lnk` tetap terbuka sehingga bisa menjalankan
operasi berulang tanpa membuka PowerShell baru.

## Port & Kredensial

Mapping default (dibuat oleh `generate.ps1`):

| Port | Username | Password |
| --- | --- | --- |
| 8001 | proxy1 | pass1 |
| 8002 | proxy2 | pass2 |
| ... | ... | ... |
| 8030 | proxy30 | pass30 |

### Mengganti kredensial

1. Edit `credentials.txt` (format: `username:password`, satu baris per instance,
   komentar boleh diawali `#`).
2. Jalankan ulang:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\generate.ps1
   powershell -ExecutionPolicy Bypass -File scripts\restart.ps1
   ```

> Pemetaan bersifat **posisional**: baris ke-`i` di `credentials.txt` dipakai
> instance/port ke-`i` (port `8000 + i`). Username tidak harus bernama `proxyNN`
> — bebas, asalkan unik. (Nama instance `proxy01` di config berbeda dari
> username default `proxy1`, dan itu normal.)

### Mengubah jumlah/port instance

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1 -Count 30 -BasePort 8001
powershell -ExecutionPolicy Bypass -File scripts\start.ps1 -Count 30 -BasePort 8001
```

> Catatan: `generate.ps1` menulis **path absolut** di `config\*.conf`. Jika
> project dipindah ke folder lain, jalankan ulang `generate.ps1`.

---

## Test Manual

Contoh dari spesifikasi (via curl):

```
curl -x http://proxy1:pass1@127.0.0.1:8001 https://api.ipify.org
curl -x http://proxy2:pass2@127.0.0.1:8002 https://api.ipify.org
```

Di aplikasi lain (browser, dsb.), isi konfigurasi proxy dengan
`127.0.0.1:<port>` dan aktifkan autentikasi dengan username/password di atas.

---

## Keamanan

- **Bind hanya `127.0.0.1`** — setiap config memakai `-i127.0.0.1` pada
  service `proxy`. Tidak ada instance yang bind ke `0.0.0.0`.
- **Jangan ubah `BindAddress` ke `0.0.0.0`** dan jangan buka port 8001–8030
  di Windows Firewall ke LAN/Internet.
- **Basic Auth wajib aktif** — `auth strong` + `users` per instance.
  `test.ps1` memverifikasi bahwa request tanpa kredensial ditolak (407).
- **Password tidak di-hardcode di script** — password hidup di
  `credentials.txt` dan `config\proxyXX.users`, yang dibuat saat runtime
  oleh `generate.ps1`.
- **Permission file** — `generate.ps1` membatasi akses `credentials.txt`,
  `*.users`, dan `*.conf` ke user yang menjalankan script (via
  `icacls /inheritance:r /grant:r <user>:F`). Best-effort: jika gagal,
  muncul warning.
- **`-olSO_EXCLUSIVEADDRUSE`** dipakai agar proses lain tidak bisa
  membajak port yang sama.
- **`proxy-list.txt` berisi kredensial plaintext** — jangan dibagikan,
  jangan di-commit (sudah di `.gitignore`).
- Karena hanya listen di loopback, Windows Firewall umumnya tidak meminta
  izin inbound — dan memang tidak boleh dibuka ke jaringan.

---

## Logging & Troubleshooting

- Setiap instance punya log sendiri dengan nama tetap: `logs\proxy01.log` …
  `logs\proxy30.log` — error satu instance langsung terlihat di file-nya
  sendiri.
- Jika `start.ps1` melaporkan `FAILED to start`, buka log instance tersebut,
  misalnya:

  ```powershell
  Get-Content logs\proxy01.log -Tail 20
  ```

- **Port sudah dipakai**: cek dengan `netstat -ano | findstr 8001` — matikan
  proses lain yang memakai port tersebut, atau gunakan `-BasePort` lain.
- **Test gagal semua**: cek koneksi internet (proxy butuh akses keluar).
- **Kredensial salah**: pastikan `credentials.txt` sesuai format
  `username:password` lalu jalankan ulang `generate.ps1` dan `restart.ps1`.
- Semua proxy dihentikan dengan:

  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\stop.ps1
  ```

---

## Catatan Tambahan

- 30 instance = 30 proses `3proxy.exe` terpisah (cek via Task Manager atau
  `scripts\status.ps1`).
- Tanpa upstream proxy (default), semua instance memakai IP publik Windows
  yang sama — lihat peringatan di atas.
- Project ini hanya mengelola proses sebagai *background process* milik user
  yang menjalankan `start.ps1`. Untuk auto-start saat boot, daftarkan
  `start.ps1` di Task Scheduler (opsional, di luar cakupan).
