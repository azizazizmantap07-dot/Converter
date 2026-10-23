# Proxy Converter — Aplikasi Android

Aplikasi Android **offline** untuk mengonversi tautan berbagi **VMess**, **VLESS**, dan **Trojan** menjadi konfigurasi **Clash Meta (Mihomo)** (YAML) dan **Sing-box** (JSON).

APK dibangun secara otomatis melalui **GitHub Actions**. Anda tidak perlu menginstal Android Studio di komputer lokal.

## Fitur

- Sepenuhnya offline (tidak mengirim data ke server)
- Parsing `vmess://`, `vless://`, `trojan://`
- Target keluaran: Clash Meta YAML, Sing-box JSON, atau keduanya
- Mode minimal (hanya daftar proxies/outbounds) atau kerangka konfigurasi lengkap
- Tempel dari clipboard, salin hasil, bagikan file, atau simpan
- Dukungan Reality, XTLS Vision, WebSocket, gRPC, uTLS fingerprint, dan parameter modern lainnya


## Template mode minimal & lengkap

Aplikasi menyematkan empat template resmi di `assets/templates/`:

| Mode | Clash | Sing-box |
|------|-------|----------|
| Minimal | `template-clash-minimal.yaml` | `template-Singbox-minimal.json` |
| Lengkap | `template-clash-lengkap.yaml` | `template-Singbox-lengkap.json` |
| **Custom** | Generator modular dinamis | Generator modular dinamis |

Pada **Mode Custom**, Anda dapat memilih sendiri:
- Addon DNS: Cloudflare, Google, AdGuard (Anti-Ads), Quad9, Custom DoH URL; Secondary DNS; DNS Strategy (IPv4 Only / Prefer IPv4 / Prefer IPv6); Fake-IP; Direct DNS perbankan
- Addon Rules: Anti-Ads, Layanan AI (ChatGPT/Claude), Streaming Media, Gaming, Bypass Bank & Domestik Indonesia, Blokir BitTorrent / P2P, Blokir QUIC, serta Custom Rules mandiri
- Addon Geo: GeoIP Indonesia Direct, Private/LAN Direct, Sub-grup regional otomatis (SG, ID, HK, JP, US, KR, TW, EU)
- Addon Routing: Nama grup utama, Mixed Port, Interval URL-Test, AUTO-TERCEPAT, TUN Mode


**Clash:** converter hanya mengisi blok `proxies:` dengan akun hasil parsing. Group memakai `include-all-proxies: true`, sehingga nama proxy tidak perlu diisi manual ke group.

**Sing-box:** converter
1. mengganti placeholder `==DAFTAR_SEMUA_TAG_PROXY==` dengan tag semua akun,
2. mengisi group regional (`==TAG_SG==`, `==TAG_JP==`, …) berdasarkan kata kunci di nama node (Singapore, Japan, US, …); jika tidak ada yang cocok diganti `DIRECT`,
3. menyisipkan outbound VMess/VLESS/Trojan hasil parsing tepat sebelum outbound `DIRECT`.

Toggle **Mode minimal / Mode lengkap** di UI memilih pasangan template di atas.

## Cara build APK lewat GitHub (disarankan)

### 1. Buat repositori GitHub

1. Buat repositori baru di GitHub (misalnya `proxy-converter-android`), boleh publik atau privat.
2. Unggah seluruh isi folder ini ke repositori tersebut.

   Contoh dengan Git:

   ```bash
   cd proxy-converter-android
   git init
   git add .
   git commit -m "Initial: Proxy Converter Android"
   git branch -M main
   git remote add origin https://github.com/USERNAME/proxy-converter-android.git
   git push -u origin main
   ```

### 2. Jalankan workflow

Setelah kode di-push ke branch `main` (atau `master`):

1. Buka tab **Actions** di repositori GitHub Anda.
2. Workflow **Build Android APK** akan berjalan otomatis.
3. Setelah selesai (hijau), buka run tersebut → bagian **Artifacts** → unduh **ProxyConverter-APK**.
4. Ekstrak file ZIP, lalu instal **`ProxyConverter.apk`** di perangkat Android (izinkan instal dari sumber tidak dikenal jika diminta).

   APK yang dihasilkan **satu file saja**, berisi native library **ARM 32-bit** dan **ARM 64-bit** (tanpa x86) agar ukuran lebih kecil dan cocok untuk hampir semua ponsel Android.

### 3. Rilis berversi (opsional)

Untuk membuat release resmi:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Workflow akan membuat GitHub Release dan melampirkan APK secara otomatis.

Anda juga dapat menjalankan workflow secara manual: **Actions → Build Android APK → Run workflow**.

## Struktur proyek

```
proxy-converter-android/
├── lib/
│   ├── main.dart          # Antarmuka aplikasi
│   └── converter.dart     # Logika parsing & konversi
├── android/               # Konfigurasi Android
├── .github/workflows/
│   └── build-apk.yml      # GitHub Actions: build APK
├── pubspec.yaml
└── README.md
```

## Build lokal (opsional)

Jika Anda memiliki Flutter SDK:

```bash
flutter pub get
flutter run                 # debug di emulator / perangkat
flutter build apk --release --target-platform android-arm,android-arm64
# APK: build/app/outputs/flutter-apk/app-release.apk
```

## Catatan

- APK release yang dihasilkan workflow menggunakan signing debug agar mudah di-sideload untuk penggunaan pribadi. Untuk distribusi Play Store, ganti `signingConfig` di `android/app/build.gradle` dengan keystore Anda sendiri.
- Aplikasi hanya menghasilkan file konfigurasi. Penggunaan proxy tunduk pada hukum dan kebijakan jaringan setempat.

## Lisensi

Disediakan apa adanya untuk keperluan pribadi dan edukasi.
