# Proxy Converter — Panduan Lengkap Penggunaan

Aplikasi Android **offline** untuk mengonversi tautan berbagi **VMess**, **VLESS**, dan **Trojan** menjadi konfigurasi siap pakai:

| Format | Ekstensi | Klien yang umum |
|--------|----------|-----------------|
| **Clash Meta / Mihomo** | `.yaml` | Clash Meta for Android, Clash Verge, FlClash, dll. |
| **Sing-box** | `.json` | Sing-box (SFA), NekoBox, dll. |

Semua proses berjalan di perangkat. **Tidak ada data yang dikirim ke server.**

---

## Daftar isi

1. [Instalasi APK](#1-instalasi-apk)
2. [Alur kerja dasar](#2-alur-kerja-dasar)
3. [Format input akun](#3-format-input-akun)
4. [Pilihan format output](#4-pilihan-format-output)
5. [Mode Minimal](#5-mode-minimal)
6. [Mode Lengkap](#6-mode-lengkap)
7. [Mode Custom](#7-mode-custom)
8. [Input Bug & Wildcard](#8-input-bug--wildcard)
9. [Hasil konversi, salin, bagikan, simpan](#9-hasil-konversi-salin-bagikan-simpan)
10. [Skenario penggunaan](#10-skenario-penggunaan)
11. [Kompatibilitas protokol](#11-kompatibilitas-protokol)
12. [Izin penyimpanan](#12-izin-penyimpanan)
13. [Build APK (pengembang)](#13-build-apk-pengembang)
14. [Pemecahan masalah](#14-pemecahan-masalah)

---

## 1. Instalasi APK

1. Unduh artifact **ProxyConverter-APK** dari GitHub Actions (atau release).
2. Ekstrak ZIP → pasang **`ProxyConverter.apk`**.
3. Izinkan instal dari sumber tidak dikenal jika diminta sistem.
4. APK mendukung **ARM 32-bit** dan **ARM 64-bit** (hampir semua ponsel Android).

Saat pertama dibuka:

- Animasi peluncuran singkat.
- Dialog **Izin Penyimpanan** muncul **sekali saja** (penting untuk Android 9 ke bawah agar bisa menulis ke folder Download). Pilih **Izinkan** atau **Nanti saja**.

---

## 2. Alur kerja dasar

```
Tempel / ketik link akun
        ↓
Pilih format output (Clash / Sing-box / keduanya)
        ↓
Pilih mode (Minimal / Lengkap / Custom)
        ↓
(Opsional) Input Bug + Wildcard
        ↓
Tekan « Konversi & Perbarui Konfigurasi »
        ↓
Salin / Bagikan / Simpan ke Download
        ↓
Impor file ke aplikasi proxy Anda
```

Tombol cepat di area input:

| Tombol | Fungsi |
|--------|--------|
| **Tempel** | Ambil teks dari clipboard, lalu konversi |
| **Hapus** | Kosongkan kotak input |

Setelah input valid, aplikasi menampilkan **Node Terdeteksi** (nama, protokol, server, label region jika dikenali dari nama).

---

## 3. Format input akun

### Aturan penting

- **Satu link per baris** (pisahkan dengan Enter).
- Boleh **mencampur** VMess, VLESS, dan Trojan dalam satu input.
- Baris kosong dan baris yang diawali `#` diabaikan.
- Banyak akun sekaligus didukung.

### Contoh input valid

```text
vmess://eyJhZGQiOiIxLjIuMy40IiwiYWlkIjoiMCIsImlkIjoi...
vless://uuid@host:443?encryption=none&security=reality&...#Nama-Node
trojan://password@host:443?security=tls&type=ws&...#Trojan-SG
```

### Yang didukung dari link

| Parameter | VMess | VLESS | Trojan |
|-----------|:-----:|:-----:|:------:|
| UUID / password | ✓ | ✓ | ✓ |
| TLS / Reality | ✓ | ✓ | ✓ |
| SNI / servername | ✓ | ✓ | ✓ |
| WebSocket / gRPC / HTTP / H2 / HTTPUpgrade | ✓ | ✓ | ✓ |
| Path & Host header | ✓ | ✓ | ✓ |
| uTLS fingerprint (`fp`) | ✓ | ✓ | ✓ |
| Flow (mis. `xtls-rprx-vision`) | — | ✓ | — |
| ALPN, insecure / skip-cert | ✓ | ✓ | ✓ |

---

## 4. Pilihan format output

Di bagian **Format Hasil**:

| Opsi | Hasil |
|------|--------|
| **Clash Meta** | Hanya YAML |
| **Sing-box** | Hanya JSON |
| **Keduanya** | YAML dan JSON (tab hasil bisa diganti) |

Pada mode **Custom**, addon yang hanya relevan untuk satu core (mis. Fake-IP / Mixed Port = Clash) **disembunyikan** jika format yang dipilih tidak memakainya, agar UI lebih bersih.

---

## 5. Mode Minimal

Konfigurasi **benar-benar basic** — tanpa rule-set remote.

### Isi yang dihasilkan

**Clash**

- Port mixed, DNS fake-IP sederhana (dengan `fake-ip-filter` untuk domain lokal)
- `proxy-server-nameserver` memakai IP biasa (UDP) lebih dulu, DoH sebagai cadangan — agar domain server proxy tetap ter-resolve di jaringan terbatas / paket bug yang memblokir DoH
- Grup `PILIH-PROXY` (select) + `AUTO-TERCEPAT` (url-test)
- Rules: `GEOIP,LAN,DIRECT` lalu `MATCH,PILIH-PROXY` (selain jaringan lokal, semua lewat proxy)

**Sing-box**

- DNS: resolver sistem (`local`) untuk domain server proxy + DoH lewat proxy
- Inbound **TUN** (agar semua lalu lintas perangkat masuk, seperti di Sing-box for Android) + mixed `127.0.0.1:2080`
- QUIC/HTTP3 ditolak agar aplikasi turun ke TCP yang stabil lewat proxy
- Selector + urltest + DIRECT
- Route: sniff, hijack-dns, private → DIRECT, final → proxy
- `default_domain_resolver` (kompatibel Sing-box modern)
- **Tanpa** remote rule-set

### Cocok untuk

- Uji cepat apakah akun hidup
- Perangkat lemah / ingin config kecil
- Pemula yang hanya butuh “semua lewat proxy”

---

## 6. Mode Lengkap

Memakai template siap pakai dengan banyak rule-set layanan, DNS berlapis, grup failover & load-balance.

### Karakteristik

- **Tanpa grup regional** (SG/JP/US, dll. sudah dihapus agar lebih sederhana)
- Rule-set remote (iklan, streaming, AI, game, GeoIP, dll.)
- Grup layanan (ADBLOCK, AI, STREAMING, …) di template Clash/Sing-box
- Remote rule-set Sing-box memakai `http_client: default-http` (detour proxy diatur di `http_clients`); field `download_detour` sudah deprecated dan bentrok dengan `http_client` di 1.14+
- `route.default_domain_resolver` disetel ke resolver sistem (`local`)

### Cocok untuk

- Pemakaian harian dengan routing iklan / streaming / AI
- Tidak ingin mengatur addon satu per satu

### Cara pakai

1. Pilih **Lengkap**.
2. Tempel akun → **Konversi**.
3. Impor YAML/JSON ke klien. Pastikan klien bisa mengunduh rule-set (akses internet saat pertama load).

---

## 7. Mode Custom

Membangun konfigurasi dari nol lewat **Custom Studio** (tab Rules, DNS, Geo, Routing).

### Default awal (mengikuti mode Minimal)

Saat Mode Custom pertama dibuka, centang **hidup hanya untuk yang dipakai Mode Minimal**
(Clash maupun Sing-box). Yang tidak ada di Minimal **tidak dicentang**.

| Addon | Default | Alasan (isi template Minimal) |
|-------|:-------:|-------------------------------|
| Fake-IP (Clash) | ✓ | Clash Minimal memakai `enhanced-mode: fake-ip` |
| Bypass Private & LAN | ✓ | Clash `GEOIP,LAN,DIRECT` · Sing-box `ip_is_private → DIRECT` |
| Grup AUTO-TERCEPAT | ✓ | Ada di kedua Minimal |
| Blokir QUIC (UDP 443) | ✓ | Sing-box Minimal menolak QUIC |
| Primary / Secondary DoH | Cloudflare / Google | Sama dengan nameserver Minimal |
| DNS Strategy | IPv4 Only | Sama dengan Minimal |
| Anti-Ads, AI, Streaming, Gaming | — | Tidak ada di Minimal |
| Bypass Layanan ID (bank), Direct DNS Perbankan | — | Tidak ada di Minimal |
| Blokir BitTorrent / P2P | — | Tidak ada di Minimal |
| Bypass GeoIP Indonesia | — | Tidak ada di Minimal |
| TUN Mode | — | Clash Minimal: `tun.enable: false`. Sing-box selalu menyertakan TUN di Custom, tidak bergantung centang ini |

### Preset cepat

| Preset | Efek ringkas |
|--------|----------------|
| **Minimalis** | Sedikit fitur, ringan |
| **Seimbang** | Anti-Ads, AI, Streaming, bypass bank & blokir torrent aktif |
| **Full Fitur** | Hampir semua addon aktif |
| **Gaming** | Fokus latency / game |
| **Streaming** | Fokus media |
| **Anti-Ads** | Blokir iklan dominan |

### Tab Rules

| Addon | Fungsi |
|-------|--------|
| Anti-Ads | Tolak domain iklan (rule-set). Grup `ADBLOCK` di Clash (REJECT / REJECT-DROP / DIRECT / proxy) dan Sing-box (REJECT / DIRECT / proxy), default REJECT |
| AI (ChatGPT, Claude, …) | Arahkan ke grup AI |
| Streaming | Netflix dll. ke grup streaming |
| Gaming | Traffic game ke grup game |
| Bypass Bank & Domestik ID | Grup `FINANSIAL-BANK` (bank, e-wallet, gov) dan `E-COMMERCE` (marketplace), default DIRECT, bisa dialihkan ke proxy — Clash & Sing-box |
| Blokir BitTorrent / P2P | Grup `DOWNLOAD-TORRENT` di Clash dan Sing-box (default REJECT); Sing-box memakai outbound `REJECT` (lubang hitam) karena `block` sudah dihapus di 1.13 |
| Blokir QUIC | UDP 443 → REJECT |
| **Custom Rules** | Aturan mandiri: DOMAIN-SUFFIX, DOMAIN-KEYWORD, IP-CIDR, GEOIP → DIRECT / REJECT / grup |

### Tab DNS

| Opsi | Keterangan |
|------|------------|
| Primary DoH | Cloudflare, Google, AdGuard, Quad9, atau **URL DoH kustom** |
| Secondary DoH | Fallback |
| DNS Strategy | `ipv4_only` / prefer IPv4 / prefer IPv6 |
| Fake-IP | **Clash saja** — mode fake-IP |
| Direct DNS perbankan | Domain bank resolve lewat DNS lokal / policy |

### Tab Geo

| Opsi | Keterangan |
|------|------------|
| Bypass GeoIP Indonesia | IP ID → DIRECT |
| Bypass Private & LAN | 192.168.x.x, domain lokal → DIRECT |

> Grup regional otomatis **tidak lagi** disediakan (sengaja dihapus).

### Tab Routing

| Opsi | Keterangan |
|------|------------|
| Nama Grup Utama | Default `PILIH-PROXY` |
| Mixed Port | Port mixed Clash (default 7892, sama dengan Minimal/Lengkap) — **Clash saja** |
| Interval URL-Test | 60 / 180 / 300 / 600 detik |
| Grup AUTO-TERCEPAT | Url-test otomatis |
| TUN Mode | TUN inbound (Clash/Sing-box sesuai generator) |

### Label core (saat format = Keduanya)

- Badge **CLASH** / **SING-BOX** menandai addon milik core mana.
- Saat hanya Clash atau hanya Sing-box dipilih, addon yang tidak relevan disembunyikan.

---

## 8. Input Bug & Wildcard

Fitur **opsional** untuk memodifikasi server / SNI / Host pada **semua** node hasil parse sebelum ditulis ke config.

### Cara pakai

1. Isi **Input Bug** (contoh: `Bug.com`). Untuk banyak akun (**multi bug**), tulis satu bug per baris (tekan Enter) — bug baris ke-N dipakai akun ke-N sesuai urutan akun; bila bug lebih sedikit dari akun, daftar diulang dari awal, dan satu bug dipakai semua akun.
2. Card **Wildcard** aktif (sebelumnya redup dan tidak bisa ditekan).
3. Ketuk Wildcard → pilih salah satu mode.
4. Konversi (otomatis jika sudah ada node).

### Mode Wildcard

| Mode | Efek (contoh bug = `Bug.com`) |
|------|-------------------------------|
| **Wildcard biasa** | `server` = Bug.com<br>`SNI` / Host = `Bug.com.<server-atau-sni-asli>` |
| **Timpa SNI** | Hanya SNI/servername diganti Bug.com; server tetap asli |
| **Timpa server & WS Host** | `server` = Bug.com dan header Host = Bug.com |
| **Timpa server saja** | Hanya `server` diganti Bug.com; SNI, Host, dan TLS tetap asli |

- Tombol **×** atau “Nonaktifkan wildcard” membatalkan modifikasi.
- Jika Input Bug dikosongkan, wildcard otomatis nonaktif.
- Menghidupkan **Multi Serangga** saat Wildcard utama aktif memunculkan pop up peringatan bergaya tema gelap-indigo dengan animasi (ikon peringatan membal dan berdenyut, panah alur Wildcard utama → Multi Serangga bergerak, tombol mengecil halus + getar saat disentuh): Multi Serangga memakai Wildcard miliknya sendiri. *Lanjutkan* menonaktifkan Wildcard utama, menghidupkan Multi Serangga, dan membuka Opsi lanjutan; *Batal* membiarkannya mati.
- Berlaku untuk **semua mode** (Minimal, Lengkap, Custom) dan kedua format.

### Multi Serangga (opsional)

Menggandakan setiap akun menjadi beberapa outbound. Cukup **dua langkah**:

1. Hidupkan toggle **Multi Serangga**.
2. Isi **Jumlah serangga / akun** (2–20).

Penamaan dibuat **otomatis**, tidak ada daftar yang perlu diketik:

| Akun | Jumlah | Hasil nama outbound |
|------|--------|---------------------|
| `SG-Premium` | 3 | `SG-Premium-1`, `SG-Premium-2`, `SG-Premium-3` |

- Server, SNI, dan Host tetap milik akun asli (dan hasil Wildcard bila aktif), jadi koneksi tidak berubah.
- Nama dijamin unik di seluruh hasil; jika dua akun bernama sama, salinan berikutnya diberi akhiran `_2`, `_3`, ….
- Contoh nama dan perkiraan jumlah outbound tampil langsung di kartu; setelah konversi, status menampilkan total outbound.
- **Opsional:** buka *Opsi lanjutan* lalu isi **Wildcard** (satu bug per baris, jadi tiap serangga bisa memakai bug berbeda). Daftar itu dipakai sebagai bug tiap serangga secara bergiliran. Pilih **Terapkan juga ke** (sama dengan menu Wildcard): *Wildcard biasa* (server = bug, SNI/Host = bug.asli), *Timpa SNI* (hanya SNI), *Server & WS Host* (server + Host header, default), atau *Server saja*. Biarkan daftar kosong untuk mode otomatis.
- **Wildcard utama dan Wildcard Multi Serangga tidak bisa aktif bersamaan.** Yang aktif lebih dulu mengunci yang lain (tampil redup dan tidak bisa ditekan). Kunci terbuka setelah yang aktif dinonaktifkan (kosongkan daftar / matikan Multi Serangga, atau tekan ✕ pada kartu Wildcard).

---

## 9. Hasil konversi, salin, bagikan, simpan

Setelah konversi berhasil:

| Aksi | Keterangan |
|------|------------|
| **Tab Clash / Sing-box** | Ganti pratinjau hasil (jika format = keduanya) |
| **Salin** | Salin seluruh teks config ke clipboard |
| **Bagikan** | Share sheet sistem (kirim ke aplikasi lain) |
| **Simpan** | Simpan ke `/storage/emulated/0/Download/` |

### Dialog nama file (Simpan)

1. Muncul popup bertema gelap.
2. Ubah nama file (opsional) — ekstensi `.yaml` / `.json` otomatis.
3. **Lewati** → nama default (`clash_config_...` / `singbox_config_...`).
4. **Simpan** → tulis file.
5. Tap di luar dialog = batalkan.

---

## 10. Skenario penggunaan

### A. Satu akun VMess, hanya Clash, mode Minimal

1. Format: **Clash Meta**.
2. Mode: **Minimal**.
3. Tempel satu baris `vmess://...`.
4. Konversi → Simpan → impor di Clash Meta.

### B. 20 akun campur VMess + VLESS + Trojan, mode Lengkap, kedua format

1. Format: **Keduanya**.
2. Mode: **Lengkap**.
3. Tempel 20 baris link (protokol boleh acak).
4. Konversi → unduh YAML dan JSON sesuai kebutuhan klien.

### C. Mode Custom anti-iklan + bypass bank, hanya Sing-box

1. Format: **Sing-box**.
2. Mode: **Custom**.
3. Preset **Anti-Ads** atau centang Anti-Ads + Bypass Bank.
4. Konversi → impor JSON ke Sing-box.
5. Pastikan tidak ada outbound `type: dns` (sudah dihapus di versi terbaru generator).

### D. Akun Reality + Vision, mode Custom full

1. Link VLESS dengan `security=reality`, `flow=xtls-rprx-vision`, `pbk`, `sid`, `fp`.
2. Mode Custom / Lengkap.
3. Output Clash memakai `reality-opts` + `client-fingerprint`; Sing-box memakai `tls.reality` + `utls`.

### E. Bug host provider (SNI khusus)

1. Isi Input Bug: hostname bug dari provider.
2. Pilih **Timpa SNI** atau **Wildcard biasa** sesuai instruksi provider.
3. Konversi ulang.

### F. Hanya uji node tanpa rule rumit

1. Mode **Minimal**.
2. Tanpa Bug/Wildcard.
3. Config kecil, cepat di-load.

---

## 11. Kompatibilitas protokol

Generator mengikuti format modern:

**Clash Meta (Mihomo ≥ 1.19)**

- Fingerprint **per-proxy** (`client-fingerprint`), bukan global.
- Trojan: field `sni`; VMess/VLESS: `servername`.
- VLESS: `encryption: none` default; Reality via `reality-opts`.

**Sing-box (1.12+ / 1.14+)**

- `route.default_domain_resolver` wajib (dipakai resolver sistem `local`: `dns-local` di Minimal, `dns-system` di Lengkap/Custom).
- Remote rule-set: `http_client: default-http` (tanpa `download_detour`).
- **Tidak** memakai outbound `type: "dns"` (sudah dihapus di 1.13).
- DNS query: rule `action: hijack-dns`.
- Transport `ws` / `httpupgrade` / `grpc` / `http`.

---

## 12. Izin penyimpanan

| Perilaku | Keterangan |
|----------|------------|
| Dialog saat install | Hanya **sekali** sejak aplikasi diinstal |
| Android 10+ | Sering tidak menampilkan izin “Storage” klasik di setelan; menulis ke Download tetap dicoba saat **Simpan** |
| Android 9 ke bawah | Izin `WRITE_EXTERNAL_STORAGE` membantu keberhasilan simpan |
| Menolak izin | App tetap bisa dipakai; fitur **Salin** / **Bagikan** tetap jalan |

---

## 13. Build APK (pengembang)

### Lewat GitHub Actions (disarankan)

1. Push kode ke branch `main` / `master`.
2. Workflow **Build Android APK** berjalan otomatis.
3. Artifact: **satu file** `ProxyConverter.apk` (ARM 32 + 64).
4. Opsional: tag `v1.0.0` → GitHub Release.

Perintah build yang dipakai CI:

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

### Lokal

```bash
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64
# Hasil: build/app/outputs/flutter-apk/app-release.apk
```

### Struktur penting

```
lib/
  main.dart       # UI, mode, bug/wildcard, simpan
  converter.dart  # Parse link, Clash/Sing-box, mode Custom
  splash.dart     # Animasi launch + izin sekali
assets/templates/
  template-clash-minimal.yaml
  template-clash-lengkap.yaml
  template-Singbox-minimal.json
  template-Singbox-lengkap.json
.github/workflows/build-apk.yml
```

---

## 14. Pemecahan masalah

| Gejala | Kemungkinan penyebab | Solusi |
|--------|----------------------|--------|
| “Tempel minimal satu link…” | Input kosong / format salah | Pastikan baris diawali `vmess://`, `vless://`, atau `trojan://` |
| Node tidak terdeteksi | Link rusak / terpotong | Salin ulang link utuh satu baris |
| Sing-box: dns outbound deprecated | Config lama | **Konversi ulang** dengan app versi terbaru |
| Sing-box: default_domain_resolver / rule-set HTTP | Config lama | Konversi ulang (sudah diperbaiki di generator) |
| Gagal Simpan ke Download | Izin / path | Gunakan **Bagikan**, atau izinkan penyimpanan di setelan app (Android lama) |
| Wildcard tidak bisa ditekan | Input Bug kosong | Isi dulu field Input Bug |
| Sing-box tidak konek internet | Config lama: tanpa TUN (Minimal) / domain server di-resolve lewat DoH-UDP publik | **Konversi ulang** dengan app versi terbaru — Minimal kini punya TUN dan resolver sistem. Di Custom, hidupkan addon **TUN** bila memakai Sing-box for Android |
| Sing-box Lengkap/Custom tidak konek padahal Minimal konek | `override_android_vpn` membuat TUN sendiri jadi upstream (loop); `dns-local` memakai DoH langsung yang diblokir; Custom tanpa TUN / memakai outbound `block` & field `geoip` yang sudah dihapus | **Konversi ulang** — sudah diperbaiki: `override_android_vpn` dihapus, `dns-local` = resolver sistem, TUN selalu aktif di Custom, REJECT memakai `action: reject` (custom rule) / outbound `REJECT` (grup ADBLOCK & DOWNLOAD-TORRENT), GEOIP memakai rule-set |
| Sing-box Lengkap/Custom gagal start di jaringan bug | Rule-set diunduh lewat DIRECT dari GitHub saat pertama start | Jalankan sekali di jaringan biasa agar rule-set tersimpan di cache, atau pakai mode Minimal |
| Clash tidak konek di paket bug / jaringan terbatas | Domain server proxy tidak ter-resolve (DoH diblokir) | **Konversi ulang** — semua mode kini memakai `proxy-server-nameserver` IP biasa (UDP) lebih dulu |
| Clash masih tidak konek padahal akun hidup | Pengaturan klien/inti | Coba hapus baris `client-fingerprint: chrome` pada node, atau samakan `mixed-port` dengan yang dipakai aplikasi/modul (default minimal: 7892) |
| Rule-set tidak terunduh | Offline / firewall | Buka internet saat pertama load config Lengkap/Custom ber-rule-set |
| Custom konek tapi tanpa internet (Sing-box atau Clash) | Config Custom lama berbeda dari Minimal/Lengkap: QUIC ditolak lewat `port 443 + udp` (bukan `protocol: quic`), `rules: []`/`rule_set: []` kosong & `http_clients` selalu ada; Clash memakai rule-provider `private.mrs` yang harus diunduh saat start, nama grup berisi emoji, `mixed-port` 7890, dan custom rule bisa menunjuk grup AI/STREAMING/GAME yang sudah dimatikan; custom DoH kehilangan path-nya | **Konversi ulang** dengan versi terbaru — Custom kini berbentuk sama dengan Minimal bila addon belum dinyalakan, lalu hanya menambah apa yang dipilih. Preset Seimbang/Minimalis tidak lagi mematikan blokir QUIC |
| Custom + addon rule-set (Anti-Ads/AI/Streaming/GeoIP, atau preset Seimbang/Gaming/Privasi) gagal start | Rule-set remote diunduh lewat proxy saat start; bila proxy belum bisa dihubungi dan belum ada cache, Sing-box berhenti dengan `initialize rule-set` | Jalankan sekali dengan Minimal/jaringan yang pasti konek agar rule-set tersimpan di cache, atau matikan addon rule-set |

---

## Ringkasan mode

| Mode | Rule-set remote | Addon UI | Ukuran config | Untuk siapa |
|------|:---------------:|:--------:|---------------|-------------|
| **Minimal** | Tidak | Tidak | Kecil | Uji cepat, sederhana |
| **Lengkap** | Ya (template) | Tidak | Besar | Harian siap pakai |
| **Custom** | Opsional per centang | Ya (Studio) | Sesuai pilihan | Kontrol penuh |

---

**Proxy Converter** — offline, multi-akun, multi-protokol, Clash Meta & Sing-box.
