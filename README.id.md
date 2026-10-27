<div align="center">

<img src="assets/swara-mark.png" width="120" alt="Logo Swara">

# 🎵 Swara: Pemutar Musik Offline

**Putar musik di HP tanpa internet, dengan metadata dan lirik otomatis, plus dashboard analitik kebiasaan mendengarkanmu.**

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white)
![Release](https://img.shields.io/github/v/release/nekonaru/swara?style=flat-square&color=blue)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square)
![CI](https://github.com/nekonaru/swara/actions/workflows/build-apk.yml/badge.svg)

</div>

[English](README.md) | **Bahasa Indonesia**

## ✨ Tentang Project

**Swara** adalah aplikasi Flutter ringan yang memutar musik langsung dari penyimpanan HP - tanpa akun, tanpa iklan, tanpa internet. Koleksimu di-scan sekali lalu tersimpan di database lokal, kemudian judul, artis, cover album, genre, bahkan lirik dilengkapi otomatis lewat internet. Aktivitas mendengarkan dirangkum di dashboard analitik, dan semuanya tetap bisa dipakai offline setelahnya.

> _"Koleksi musikmu, didengarkan dengan tenang, bahkan tanpa internet."_

## 🎯 Fitur

| Fitur | Keterangan |
|-------|------------|
| ▶️ **Putar offline** | Scan dan putar musik langsung dari penyimpanan HP |
| 🔔 **Putar di background** | Foreground service Android asli dengan MediaSession: kontrol dari notifikasi dan lockscreen (play/pause/next/previous) |
| 🔀 **Acak dan ulangi** | Shuffle, ulangi mati / semua / satu lagu, plus sleep timer durasi atau jumlah lagu |
| ⏱️ **Mini player** | Selalu terlihat di semua halaman; kontrol kecepatan 0.5x sampai 2x |
| 📝 **Antrean putar** | Tambah lagu untuk diputar berikutnya atau di akhir, reorder dan hapus |
| 👆 **Multi-select** | Long-press untuk pilih banyak lagu, lalu favoritkan atau tambah ke playlist sekaligus |
| 🌐 **Metadata otomatis** | Judul, artis, cover album, dan genre via iTunes Search API |
| 📡 **Refresh metadata per lagu** | "Scan metadata" di menu lagu mengambil ulang satu lagu dari internet |
| 🎤 **Lirik otomatis** | Diambil via lyrics.ovh, bisa diedit manual, fallback cari di Google |
| ✏️ **Edit manual** | Perbaiki metadata dan lirik per lagu kalau hasil otomatis kurang pas |
| 📁 **Browse folder** | Jelajahi per folder asal, sembunyikan folder dari library |
| 🔤 **Navigasi A-Z** | Scrollbar huruf mengikuti jari untuk lompat cepat |
| 💿 **Playlist dan favorit** | Playlist kustom, favorit, baru diputar |
| 🤖 **Smart playlist otomatis** | Daily Mix (25 lagu segar tiap hari) dan Unplayed, dirawat otomatis |
| 🎼 **Lirik sinkron** | Lirik per baris mengikuti lagu, dengan fallback tampilan biasa |
| 😴 **Sleep timer lembut** | Volume memudar, bukan berhenti mendadak |
| 💾 **Backup dan restore** | Export dan import playlist, favorit, dan riwayat sebagai JSON |
| 🖼️ **Cover playlist** | Kolase otomatis dari cover album anggota |
| 🏆 **Rekap tahunan** | Lagu, artis, dan jam teratas tahun berjalan, bisa dibagikan sebagai gambar |
| 📋 **Simpan antrean** | Simpan antrean putar sebagai playlist sekali ketuk |
| 🌙 **Jadwal tidur** | Sleep timer jam tetap setiap malam |
| 🎚️ **Equalizer beneran** | 9 preset membentuk suara putar via DSP sistem |
| 🔍 **Pencarian toleran** | "faded alan walker" ketemu untuk "faded - alan walker" |
| 🗂️ **Pencari duplikat** | Temukan dan hapus lagu duplikat, sisakan satu per grup |
| 🖼️ **Cover hilang** | Daftar lagu tanpa cover dengan fetch ulang sekali ketuk |
| 📂 **Folder playlist** | Kelompokkan playlist ke dalam folder |
| 🔀 **Gabung playlist** | Gabungkan playlist lain, lewati yang duplikat |
| 🖼️ **Lirik hilang** | Daftar lagu tanpa lirik dengan fetch ulang sekali ketuk |
| 🎚️ **Kontrol crossfade** | Transisi 0-12 dtk + EQ custom 5-band |
| 🌑 **Hitam AMOLED** | Opsi tema gelap hitam pekat |
| 🚀 **List penuh, tanpa Load more** | Semua list tampil utuh tetap ringan, A-Z instan, shuffle mencakup semua lagu |
| 🎚️ **Kecepatan dan nada** | kecepatan putar 0.5x sampai 2.0x plus kontrol nada, langsung aktif dan bisa di reset |
| 🧠 **Acak pintar** | Memprioritaskan lagu yang jarang dan lama tidak diputar |
| 🛏️ **Jadwal tidur harian** | Sleep timer 30 menit otomatis tiap hari pada jam pilihan |
| ⚡ **Database lebih cepat** | Mode WAL, pragma di optimasi, dan index yang cocok agar sort dan lompat tetap instan |
| 🧹 **Bersihkan riwayat** | Pembersihan riwayat pendengaran lama opsional dengan konfirmasi di Pengaturan |
| ⏱️ **Waktu lirik** | Membaca tag offset dari file .lrc plus penggeser manual 100 ms |
| 🔤 **Search tahan salah ketik** | Lagu tetap ditemukan walau huruf tertukar atau salah ketik, plus saran "maksudmu" |
| 📥 **Import M3U** | Import playlist dari file .m3u, dicocokkan ke library |
| 📤 **Export M3U** | Export playlist ke file .m3u untuk pemutar lain |
| 🔁 **Ulangi A-B** | Ulangi segmen lagu untuk latihan |
| ✏️ **Edit massal** | Edit genre dan artist banyak lagu sekaligus |
| 📤 **Bagikan lagu** | Bagikan info lagu plus file audio |
| 🔥 **Streak mendengarkan** | Streak harian dan genre teratas bulan ini di dashboard |
| 🔍 **Pencarian** | Cari real-time berdasarkan judul, artis, album, folder, atau genre |
| 📊 **Dashboard** | Grafik 7 hari terakhir, lagu dan artis teratas, distribusi genre dan region |
| 🌍 **UI English dan Indonesia** | Default English; ganti ke Bahasa Indonesia di Pengaturan |
| 🎨 **Tema** | Terang, gelap, atau ikuti sistem, plus 10 warna aksen |
| 🪶 **Ringan di pustaka besar** | Pencarian, sort, dan update per baris berjalan di luar thread utama supaya tidak patah-patah |

## 📦 Requirements

- **Flutter** 3.47 atau lebih baru (channel stable)
- **JDK** 17
- **Android SDK** (API 34+)
- HP atau emulator Android (minimum Android 8.0 / API 26)

### Belum pernah pakai terminal? Ikuti ini dulu

<details>
<summary><b>Cara buka terminal di Windows</b></summary>

1. Tekan tombol **Windows**, ketik `PowerShell`, lalu tekan **Enter**
2. Jendela biru akan terbuka. Itu tempat kamu mengetik perintah
3. Semua perintah `flutter ...` atau `git ...` di panduan ini diketik di jendela itu, lalu tekan **Enter**

</details>

## 🚀 Instalasi

### Cara A: Download APK (paling gampang)

1. Buka halaman [Releases](https://github.com/nekonaru/swara/releases)
2. Download APK yang cocok dengan HP (`app-arm64-v8a-release.apk` untuk kebanyakan HP modern, `app-armeabi-v7a-release.apk` untuk yang 32-bit lama)
3. Buka di HP, izinkan instalasi dari sumber tidak dikenal bila diminta
4. Izinkan akses audio saat aplikasi pertama dibuka

### Cara B: Build dari source (untuk development / mau lihat/ubah kode)

**1. Ambil kode project ini**

<details>
<summary><b>Punya Git terinstall</b></summary>

```bash
git clone https://github.com/nekonaru/swara.git
cd swara
```

</details>

<details>
<summary><b>Tidak punya Git</b></summary>

1. Buka halaman repository di GitHub
2. Klik tombol hijau **`Code`**, pilih **`Download ZIP`**
3. Ekstrak ZIP ke folder pilihanmu
4. Di terminal, masuk ke folder hasil ekstrak, contoh:

```bash
cd Downloads/swara-main
```

</details>

**2. Install dependency dan verifikasi**

```bash
flutter pub get
flutter analyze
```

`flutter analyze` harus melaporkan **No issues found**.

**3. Build APK**

```bash
flutter build apk --release
```

Hasilnya ada di `build/app/outputs/flutter-apk/app-release.apk`.

## 🖥️ Cara Pakai

**Pertama dibuka:**
1. Izinkan akses audio saat diminta
2. Aplikasi scan musik sekali lalu simpan ke database lokal
3. Metadata dan lirik yang kurang dilengkapi otomatis per-batch kecil

**Dipakai harian:**
- Jelajahi **Perpustakaan** (tab Lagu, Album, Artis, Folder, Genre, bisa dikonfigurasi)
- Ketuk lagu untuk memutar; pakai mini player untuk kontrol dari halaman mana pun
- Swipe bawah pada player untuk minimize
- Long-press lagu untuk multi-select (favoritkan atau tambah ke playlist sekaligus)
- Buka **Dashboard** untuk melihat statistik mendengarkanmu

## 🌍 Bahasa Tampilan

UI aplikasi (menu, tombol, pesan, dan pengaturan) tersedia dalam **English** (default) dan **Bahasa Indonesia**.

1. Buka **Pengaturan**
2. Di bagian **Bahasa**, pilih **English** atau **Bahasa Indonesia**
3. Pilihan diingat antar sesi

## 🗂️ Struktur Project

```
swara/
├── lib/
│   ├── main.dart                 # entry point, provider, MaterialApp + locale
│   ├── l10n/
│   │   ├── app_en.arb            # string English (sumber utama)
│   │   ├── app_id.arb            # string Indonesia
│   │   └── gen/                  # hasil generate (jangan edit manual)
│   ├── models/                   # Song, ListeningEntry
│   ├── providers/                # state library, playlist, theme, bahasa
│   ├── screens/                  # semua halaman (library, player, dashboard, ...)
│   ├── services/                 # player, database, scanner, metadata, audio handler
│   ├── utils/                    # formatting, menu opsi lagu, transisi
│   └── widgets/                  # mini player, sleep timer, scrollbar, ...
├── l10n.yaml                     # konfigurasi lokalisasi
├── android_res_extra/            # ikon notifikasi dipasang ke APK oleh CI
├── .github/
│   └── workflows/
│       ├── build-apk.yml         # CI: build APK tiap push ke main
│       └── build.yml             # CI: build APK + draft GitHub release
├── pubspec.yaml
├── LICENSE
├── README.md                     # dokumentasi utama (English)
└── README.id.md                  # dokumentasi (Bahasa Indonesia)
```

**Menambah string baru yang tampil ke user:**
1. Tambahkan key ke `lib/l10n/app_en.arb` (English) dan `lib/l10n/app_id.arb` (Indonesia)
2. Jalankan `flutter gen-l10n`
3. Pakai via `AppLocalizations.of(context)!.namaKey`

## 🧪 Testing

Belum ada test suite. Verifikasi statis sebelum setiap push:

```bash
flutter analyze
```

Harus melaporkan **No issues found** (nol error, nol warning).

## ❓ FAQ

<details>
<summary><b>Musik berhenti saat aplikasi ke background?</b></summary>

Matikan optimasi baterai untuk Swara (Autostart / background tanpa batas di XOS, MIUI, dan sejenisnya), dan pastikan izin notifikasi diberikan.

</details>

<details>
<summary><b>Ada lagu "Unknown Artist" atau tanpa lirik?</b></summary>

Auto-fetch bergantung database publik (iTunes, lyrics.ovh). Lagu lokal/indie sering tidak ada di sana. Pakai Edit Metadata / Edit Lirik pada lagunya untuk perbaiki manual.

</details>

<details>
<summary><b>Cara ganti bahasa?</b></summary>

Pengaturan, bagian **Bahasa**, pilih English atau Bahasa Indonesia. Default-nya English.

</details>

## 👤 Author

<div align="center">

| [![Nicolas Dwi Dharma](https://github.com/github.png?size=100)](https://github.com/nekonaru) |
|:---:|
| **Nicolas Dwi Dharma** |
| [github.com/nekonaru](https://github.com/nekonaru) |

</div>

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.

<div align="center">

Dibuat oleh **Nicolas Dwi Dharma**

*Star ⭐ repo ini kalau project ini membantumu!*

</div>
