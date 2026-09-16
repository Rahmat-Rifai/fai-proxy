Buatkan sistem 30 local HTTP proxy server untuk Windows.

Spesifikasi

- Platform: Windows 10/11
- Jumlah proxy: 30 instance
- Proxy type: HTTP proxy
- Bind address: "127.0.0.1"
- Port: "8001" sampai "8030"
- Setiap instance berjalan sebagai proses/service terpisah.
- Tidak menggunakan upstream proxy untuk konfigurasi default.
- Setiap proxy memiliki Basic Authentication yang berbeda.

Kredensial

Gunakan pola:

proxy1:pass1
proxy2:pass2
proxy3:pass3
...
proxy30:pass30

Mapping:

127.0.0.1:8001 → proxy1:pass1
127.0.0.1:8002 → proxy2:pass2
127.0.0.1:8003 → proxy3:pass3
...
127.0.0.1:8030 → proxy30:pass30

Persyaratan implementasi

Gunakan software/library HTTP proxy yang native dan kompatibel dengan Windows. Jangan menggunakan WSL, Docker, Termux, atau Linux VM.

Buat project yang memiliki:

1. Script instalasi dependency.
2. Script generate konfigurasi untuk 30 proxy.
3. Script start semua proxy.
4. Script stop semua proxy.
5. Script restart semua proxy.
6. Script melihat status seluruh proxy.
7. Script test seluruh proxy.
8. Script menampilkan IP keluar masing-masing proxy.
9. File konfigurasi terpisah untuk setiap instance.
10. Logging terpisah agar error setiap instance mudah diketahui.

Gunakan struktur:

windows-proxy-pool/
├── config/
│   ├── proxy01.conf
│   ├── proxy02.conf
│   └── ... proxy30.conf
├── logs/
├── scripts/
│   ├── install.ps1
│   ├── generate.ps1
│   ├── start.ps1
│   ├── stop.ps1
│   ├── restart.ps1
│   ├── status.ps1
│   └── test.ps1
├── credentials.txt
└── README.md

Keamanan

- Semua proxy hanya boleh listen pada "127.0.0.1".
- Jangan bind ke "0.0.0.0".
- Jangan membuka port tersebut ke LAN/Internet.
- BasicAuth wajib aktif.
- Jangan menyimpan password secara hardcoded di source code jika software yang digunakan mendukung credential file/environment variable.
- Berikan permission file konfigurasi secara wajar.

Testing

Setelah semua proxy dijalankan, test:

http://127.0.0.1:8001
http://127.0.0.1:8002
...
http://127.0.0.1:8030

Gunakan "curl" atau tool HTTP yang sesuai untuk melakukan request melalui masing-masing proxy dengan BasicAuth.

Contoh:

curl -x http://proxy1:pass1@127.0.0.1:8001 https://api.ipify.org

Buat "test.ps1" yang melakukan test otomatis terhadap seluruh 30 proxy dan menghasilkan tabel:

Proxy   Port   Auth   Status   Public IP
1       8001   OK     OK       x.x.x.x
2       8002   OK     OK       x.x.x.x
...
30      8030   OK     OK       x.x.x.x

Penting

Jelaskan dengan jelas di README bahwa:

30 proxy lokal tidak berarti 30 IP publik berbeda.

Tanpa upstream proxy/VPN/network interface yang berbeda, seluruh instance akan tetap keluar menggunakan IP publik Windows yang sama.

Jangan mengklaim bahwa setiap port menghasilkan IP publik berbeda.

Sebelum membuat file, tentukan software proxy Windows yang paling cocok untuk kebutuhan ini, jelaskan alasannya secara singkat, lalu implementasikan konfigurasi lengkapnya.