# windows-proxy-pool

Sistem 30 proxy HTTP lokal untuk Windows 10/11 menggunakan 3proxy native. Setiap instance berjalan sebagai proses terpisah yang listen di `127.0.0.1` (port 8001–8030) dengan Basic Auth masing-masing.

Catatan: Seluruh instance keluar menggunakan IP publik Windows yang sama. Default konfigurasi tidak menyertakan upstream proxy.

```
127.0.0.1:8001 -> proxy1:pass1
127.0.0.1:8002 -> proxy2:pass2
...
127.0.0.1:8030 -> proxy30:pass30
```

## Persyaratan

- Windows 10 atau 11 (x64 / x86 / arm64)
- PowerShell 5.1+
- curl (bawaan Windows)
- Koneksi internet untuk mengunduh binary 3proxy saat instalasi awal

## Struktur Project

```
windows-proxy-pool/
├── bin/            # Binary 3proxy.exe (diunduh lewat install.ps1)
├── config/         # File konfigurasi (.conf) dan kredensial (.users) per instance
├── logs/           # Log per instance (proxy01.log ... proxy30.log)
├── run/            # PID file per instance
├── scripts/        # Script PowerShell untuk manajemen pool
├── shortcuts/      # Shortcut Windows (.lnk)
├── credentials.txt # Daftar user:pass sumber
└── proxy-list.txt  # Daftar proxy aktif hasil ekspor
```

## Cara Menjalankan

Buka PowerShell di folder project:

```powershell
# 1. Unduh binary 3proxy ke folder bin/
powershell -ExecutionPolicy Bypass -File scripts\install.ps1

# 2. Buat konfigurasi 30 proxy dan credentials.txt
powershell -ExecutionPolicy Bypass -File scripts\generate.ps1

# 3. Jalankan seluruh proxy, tunggu port siap, cek status, dan ekspor proxy-list.txt
powershell -ExecutionPolicy Bypass -File scripts\run.ps1
```

Atau jalankan langkah-langkah secara manual:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\start.ps1   # Start semua instance
powershell -ExecutionPolicy Bypass -File scripts\status.ps1  # Cek status proses & port
powershell -ExecutionPolicy Bypass -File scripts\test.ps1    # Tes koneksi ke internet
powershell -ExecutionPolicy Bypass -File scripts\stop.ps1    # Hentikan semua proxy
```

Untuk menu interaktif:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\menu.ps1
```

## Referensi Script

| Script | Deskripsi |
|---|---|
| `install.ps1` | Unduh binary 3proxy resmi dari GitHub release dan ekstrak ke `bin\`. |
| `generate.ps1` | Buat `config\proxyXX.conf` dan `config\proxyXX.users` dari `credentials.txt`. Batasi akses file lewat icacls. |
| `start.ps1` | Jalankan 30 proses 3proxy terpisah dan tunggu file PID terbentuk. |
| `stop.ps1` | Hentikan proses via file PID di `run\` dan bersihkan file PID basi. |
| `restart.ps1` | Matikan lalu jalankan ulang seluruh instance dan perbarui `proxy-list.txt`. |
| `status.ps1` | Tampilkan port, PID, status proses, dan status listening tiap instance. |
| `test.ps1` | Tes autentikasi: pastikan request tanpa kredensial ditolak (407) dan request ber-auth mengembalikan IP publik. |
| `export-proxies.ps1` | Ekspor proxy yang aktif ke `proxy-list.txt` (`http://user:pass@127.0.0.1:port`). |
| `run.ps1` | Jalankan runtutan: start, tunggu port listening, health check, lalu ekspor list. |
| `rotate-credentials.ps1` | Buat password acak baru (16 karakter), perbarui config, dan restart pool. |
| `install-autostart.ps1` | Daftarkan Scheduled Task agar pool otomatis berjalan saat logon. |
| `install-monitor.ps1` | Daftarkan Scheduled Task monitoring (auto-restart bila instance mati). |
| `cleanup-logs.ps1` | Hapus log yang lebih tua dari batas retensi (default: 30 hari). |

## Port & Kredensial Default

Port 8001–8030 dipetakan ke baris di `credentials.txt`:
- Port 8001: `proxy1:pass1`
- Port 8002: `proxy2:pass2`
- ...
- Port 8030: `proxy30:pass30`

Mengganti username atau password:
1. Edit file `credentials.txt` (format `username:password`, satu baris per instance).
2. Terapkan perubahan:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\generate.ps1
   powershell -ExecutionPolicy Bypass -File scripts\restart.ps1
   ```

## Tes Manual

Tes koneksi menggunakan curl:

```bash
curl -x http://proxy1:pass1@127.0.0.1:8001 https://api.ipify.org
```

Request tanpa username dan password akan ditolak dengan respons HTTP 407 (Proxy Authentication Required).

## Keamanan

- Interface loopback: Konfigurasi mengikat proxy hanya ke `127.0.0.1` (`-i127.0.0.1`). Jangan ubah ke `0.0.0.0` atau membuka port ke jaringan publik.
- Basic Auth wajib: Menggunakan direktif `auth strong` dengan file user per instance.
- Proteksi port: Menggunakan flag `-olSO_EXCLUSIVEADDRUSE` agar port tidak bisa dibajak proses lain.
- File kredensial: `credentials.txt` dan `proxy-list.txt` berisi kredensial plaintext. File ini masuk ke `.gitignore` dan tidak boleh diunggah ke internet.
