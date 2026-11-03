<div align="center">
  <img src="assets/swara-mark.png" alt="Swara logo" width="120" />
  <h1>Swara: Pemutar Musik Offline</h1>
  <p><b>Putar musik di ponselmu tanpa internet, dengan metadata dan lirik yang diambil sesuai permintaan,<br/>
  plus dashboard analitik kebiasaan mendengarkanmu.</b></p>

  <a href="https://github.com/nekonaru/swara/releases"><img src="https://img.shields.io/github/v/release/nekonaru/swara?style=flat-square&color=blue" alt="Release" /></a>
  <a href="https://github.com/nekonaru/swara/actions/workflows/build-apk.yml"><img src="https://github.com/nekonaru/swara/actions/workflows/build-apk.yml/badge.svg" alt="CI" /></a>
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Platform" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square" alt="Status" />
</div>

<br />

[English](README.md) | **Bahasa Indonesia**

> [!NOTE]
> Swara memutar musik langsung dari penyimpanan ponselmu. Internet hanya dipakai saat kamu sendiri memulai pemindaian metadata atau lirik. Pemindaian tidak pernah mulai sendiri dan bisa dihentikan kapan saja.

---

## Daftar Isi

- [Tentang](#tentang)
- [Fitur](#fitur)
- [Persyaratan](#persyaratan)
- [Instalasi](#instalasi)
- [Penggunaan](#penggunaan)
- [Bahasa Tampilan](#bahasa-tampilan)
- [Sumber Data](#sumber-data)
- [Struktur Proyek](#struktur-proyek)
- [Pengembangan](#pengembangan)
- [Pengujian](#pengujian)
- [Continuous Integration](#continuous-integration)
- [FAQ](#faq)
- [Penulis](#penulis)
- [Disclaimer](#disclaimer)
- [Lisensi](#lisensi)

---

## Tentang

**Swara** adalah aplikasi Flutter ringan yang memutar musik langsung dari penyimpanan ponselmu, tanpa akun, tanpa iklan, tanpa internet. Aplikasi memindai koleksimu sekali, lalu melengkapi judul, artis, sampul album, genre, bahkan lirik lewat internet setiap kali kamu memulai pemindaian sendiri. Pemindaian tidak pernah mulai sendiri dan bisa dihentikan kapan saja. Aktivitas mendengarkanmu dirangkum dalam dashboard analitik, dan semuanya bisa dipakai sepenuhnya offline setelahnya.

> _"Koleksi musikmu, diputar dengan tenang, bahkan tanpa internet."_

---

## Fitur

### Pemutaran

| Fitur | Deskripsi |
|-------|-----------|
| **Pemutaran offline** | Pindai dan putar musik langsung dari penyimpanan ponsel |
| **Pemutaran di latar belakang** | Foreground service Android asli dengan MediaSession: kontrol notifikasi dan layar kunci (putar/jeda/berikutnya/sebelumnya) |
| **Acak dan ulangi** | Acak, ulangi mati / semua / satu lagu, plus sleep timer berdasarkan durasi atau jumlah lagu |
| **Mini player** | Selalu terlihat di setiap halaman; kontrol kecepatan putar dari 0.5x sampai 2x |
| **Acak pintar** | Mengutamakan lagu yang jarang diputar dan lama tidak diputar |
| **Ulangi A-B** | Ulangi bagian lagu mana pun untuk latihan |

### Suara

| Fitur | Deskripsi |
|-------|-----------|
| **Equalizer sungguhan** | 9 preset yang membentuk suara pemutaran sebenarnya lewat DSP sistem |
| **Kontrol crossfade** | Transisi 0-12 detik yang bisa diatur plus EQ 5 band kustom |
| **Kecepatan dan pitch** | Kecepatan putar 0.5x sampai 2.0x plus kontrol pitch dengan penerapan langsung dan reset |

### Sleep Timer

| Fitur | Deskripsi |
|-------|-----------|
| **Sleep timer lembut** | Volume memudar perlahan, tidak berhenti mendadak |
| **Jadwal waktu tidur** | Sleep timer pada jam tertentu setiap malam |
| **Jadwal tidur harian** | Otomatis memulai sleep timer 30 menit pada waktu pilihanmu setiap hari |

### Metadata dan Lirik

| Fitur | Deskripsi |
|-------|-----------|
| **Metadata sesuai permintaan** | Judul, artis, sampul album, dan genre lewat iTunes Search API, dari pemindaian yang kamu mulai sendiri |
| **Hentikan pemindaian kapan saja** | Pemindaian metadata tidak pernah mulai sendiri, dan setiap pemindaian bisa dihentikan di tengah jalan tanpa ada yang hilang |
| **Segarkan metadata per lagu** | "Scan metadata" di menu lagu mengambil ulang satu lagu dari internet |
| **Lirik sesuai permintaan** | Diambil lewat lrclib dengan lyrics.ovh sebagai cadangan, bisa diedit manual, ada cadangan pencarian Google |
| **Edit manual** | Perbaiki metadata dan lirik per lagu saat hasil pemindaian salah |
| **Lirik tersinkron** | Lirik baris demi baris yang mengikuti lagu, dengan tampilan teks biasa sebagai cadangan |
| **Penyelarasan lirik** | Membaca tag offset dari file .lrc dan memungkinkan menggeser lirik per 100 ms |

### Pustaka dan Pencarian

| Fitur | Deskripsi |
|-------|-----------|
| **Pilih banyak** | Tekan lama untuk memilih banyak lagu, lalu jadikan favorit atau tambahkan ke playlist sekaligus |
| **Jelajah folder** | Jelajahi berdasarkan folder sumber, sembunyikan folder dari pustaka |
| **Navigasi A-Z** | Scrollbar huruf yang mengikuti jari untuk lompat cepat |
| **Pencarian** | Pencarian real-time berdasarkan judul, artis, album, folder, atau genre, dengan input yang di-debounce |
| **Pencarian toleran** | Menemukan "faded alan walker" untuk "faded - alan walker" |
| **Pencarian toleran typo** | Menemukan lagu meski huruf tertukar atau salah ketik, dengan petunjuk "maksud kamu" |
| **Bagikan lagu** | Bagikan info lagu yang sedang diputar beserta file audionya |

### Perawatan Pustaka

| Fitur | Deskripsi |
|-------|-----------|
| **Pencari duplikat** | Temukan dan hapus lagu duplikat, sisakan satu per kelompok |
| **Sampul yang hilang** | Daftar lagu tanpa sampul dengan pengambilan ulang sekali ketuk |
| **Lirik yang hilang** | Daftar lagu tanpa lirik dengan pengambilan ulang sekali ketuk |
| **Edit massal** | Ubah genre dan artis di banyak lagu sekaligus |

### Antrean dan Playlist

| Fitur | Deskripsi |
|-------|-----------|
| **Antrean putar** | Tambahkan lagu untuk diputar berikutnya atau di akhir, urutkan ulang dan hapus |
| **Simpan antrean** | Simpan antrean putar sebagai playlist dengan satu ketukan |
| **Playlist dan favorit** | Playlist kustom, favorit, baru diputar |
| **Playlist otomatis pintar** | Daily Mix (25 lagu segar setiap hari) dan Unplayed, dikelola otomatis |
| **Sampul playlist** | Kolase otomatis dari sampul album anggota playlist |
| **Folder playlist** | Kelompokkan playlist ke dalam folder |
| **Gabung playlist** | Gabungkan playlist lain, duplikat dilewati |
| **Impor/ekspor M3U** | Impor playlist dari file .m3u, ekspor kembali |

### Statistik

| Fitur | Deskripsi |
|-------|-----------|
| **Dashboard** | Grafik 7 hari terakhir, lagu dan artis teratas, distribusi genre dan wilayah |
| **Rekap tahunan** | Lagu, artis, dan jam teratas tahun ini, bisa dibagikan sebagai gambar |
| **Streak mendengarkan** | Streak hari dan genre teratas bulan ini di dashboard |

### Data dan Cadangan

| Fitur | Deskripsi |
|-------|-----------|
| **Cadangkan dan pulihkan** | Ekspor dan impor playlist, favorit, dan riwayat dalam bentuk JSON |
| **Pembersihan riwayat** | Opsional, pembersihan riwayat mendengarkan lama yang kamu konfirmasi sendiri di Pengaturan |

### Tampilan dan Bahasa

| Fitur | Deskripsi |
|-------|-----------|
| **Antarmuka Inggris dan Indonesia** | Bahasa Inggris secara default; ganti ke Bahasa Indonesia di Pengaturan |
| **Tema** | Terang, gelap, atau ikuti sistem, plus 10 warna aksen, semuanya distyling dari satu tema bersama |
| **Animasi halus** | Satu transisi halus di semua layar, plus sampul mini player yang melayang ke player |
| **AMOLED hitam** | Opsi tema gelap hitam pekat |

### Performa

| Fitur | Deskripsi |
|-------|-----------|
| **Daftar penuh, tanpa Load more** | Setiap daftar ditampilkan penuh dan tetap mulus, lompat A-Z instan, acak mencakup setiap lagu |
| **Database lebih cepat** | Mode WAL, pragma yang disetel, dan indeks yang cocok sehingga pengurutan dan lompatan tetap instan |
| **Mulus di pustaka besar** | Pencarian, pengurutan, dan pembaruan satu baris berjalan di luar main thread, dengan tampilan turunan yang di-cache dan regex yang di-hoist, jadi tidak ada yang tersendat |

---

## Persyaratan

| Dependensi | Versi Minimum | Catatan |
|------------|---------------|---------|
| **Flutter** | 3.47 | Channel stable, hanya diperlukan untuk build dari source |
| **JDK** | 17 | Hanya diperlukan untuk build dari source |
| **Android SDK** | API 34+ | Hanya diperlukan untuk build dari source |
| **Ponsel atau emulator Android** | Android 8.0 (API 26) | Diperlukan untuk menjalankan aplikasi |

> [!TIP]
> Kalau kamu hanya ingin memakai aplikasinya, kamu tidak perlu Flutter, JDK, atau Android SDK. Unduh APK dari halaman [Releases](https://github.com/nekonaru/swara/releases).

### Belum pernah memakai terminal? Mulai dari sini

<details>
<summary><b>Cara membuka terminal di Windows</b></summary>

1. Tekan tombol **Windows**, ketik `PowerShell`, lalu tekan **Enter**
2. Jendela biru akan terbuka. Di situlah kamu mengetik perintah
3. Setiap perintah `flutter ...` atau `git ...` di panduan ini diketik di jendela itu, diikuti **Enter**

</details>

---

## Instalasi

### Opsi A: Unduh APK (paling mudah)

1. Buka halaman [Releases](https://github.com/nekonaru/swara/releases)
2. Unduh APK yang sesuai dengan perangkatmu (`app-arm64-v8a-release.apk` untuk kebanyakan ponsel modern, `app-armeabi-v7a-release.apk` untuk ponsel 32-bit yang lebih lama)
3. Buka di ponselmu, izinkan instalasi dari sumber tidak dikenal jika diminta
4. Izinkan akses audio saat aplikasi pertama kali dibuka

> [!IMPORTANT]
> Berikan akses audio saat diminta, kalau tidak Swara tidak bisa melihat musikmu. Berikan juga izin notifikasi agar kontrol pemutaran di latar belakang bisa muncul.

### Opsi B: Build dari source (untuk pengembangan / membaca atau mengubah kode)

#### 1. Ambil kode proyek

<details>
<summary><b>Saya sudah menginstal Git</b></summary>

```bash
git clone https://github.com/nekonaru/swara.git
cd swara
```

</details>

<details>
<summary><b>Saya belum punya Git</b></summary>

1. Buka halaman repositori di GitHub
2. Klik tombol hijau **`Code`**, pilih **`Download ZIP`**
3. Ekstrak ZIP ke folder pilihanmu
4. Di terminal, masuk ke folder hasil ekstrak, contohnya:

```bash
cd Downloads/swara-main
```

</details>

#### 2. Instal dependensi dan verifikasi

```bash
flutter pub get
flutter analyze
```

> [!IMPORTANT]
> `flutter analyze` harus melaporkan **No issues found**.

#### 3. Build APK

```bash
flutter build apk --release
```

Hasilnya ada di `build/app/outputs/flutter-apk/app-release.apk`.

---

## Penggunaan

### Pertama kali dibuka

1. Izinkan akses audio saat diminta
2. Aplikasi memindai musikmu sekali dan menyimpannya ke database lokal
3. Mulai pemindaian metadata dari menu pustaka atau Pengaturan; pengambilan dilakukan dalam batch kecil dan bisa dihentikan kapan saja

> [!NOTE]
> Pemindaian metadata dan lirik hanya berjalan saat kamu memulainya. Setelah selesai, semuanya bisa dipakai offline.

### Penggunaan sehari-hari

- Jelajahi **Pustaka** (tab Lagu, Album, Artis, Folder, Genre, bisa dikonfigurasi)
- Ketuk lagu untuk memutar; gunakan mini player untuk mengontrol dari halaman mana pun
- Geser ke bawah pada pemutar untuk memperkecilnya
- Tekan lama pada lagu untuk pilih banyak (favorit atau tambah ke playlist sekaligus)
- Buka **Dashboard** untuk melihat statistik mendengarkanmu

---

## Bahasa Tampilan

Antarmuka aplikasi (menu, tombol, pesan, dan pengaturan) tersedia dalam **Bahasa Inggris** (default) dan **Bahasa Indonesia**.

1. Buka **Pengaturan**
2. Di bawah **Bahasa**, pilih **English** atau **Bahasa Indonesia**
3. Pilihanmu diingat antar sesi

---

## Sumber Data

Swara hanya terhubung ke internet saat kamu memulai pemindaian sendiri. Layanan publik yang dipakai:

| Tujuan | Sumber |
|--------|--------|
| Judul, artis, sampul album, genre | iTunes Search API |
| Lirik | lrclib, dengan lyrics.ovh sebagai cadangan |
| Lirik pilihan terakhir | Cadangan pencarian Google |

> [!NOTE]
> Ini adalah database publik, jadi lagu lokal atau indie sering tidak ada di sana. Gunakan Edit Metadata / Edit Lyrics pada lagu untuk memperbaikinya secara manual.

---

## Struktur Proyek

```
swara/
├── lib/
│   ├── main.dart                 # entry point, provider, MaterialApp + locale
│   ├── l10n/
│   │   ├── app_en.arb            # string Inggris (sumber utama)
│   │   ├── app_id.arb            # string Indonesia
│   │   └── gen/                  # lokalisasi hasil generate (jangan diedit manual)
│   ├── models/                   # Song, ListeningEntry
│   ├── providers/                # state pustaka, playlist, tema, bahasa
│   ├── screens/                  # semua halaman (pustaka, pemutar, dashboard, ...)
│   ├── services/                 # pemutar, database, pemindai, metadata, audio handler
│   ├── theme/                    # satu sumber semua default visual
│   ├── utils/                    # format, menu opsi lagu, transisi
│   └── widgets/                  # mini player, sleep timer, scrollbar, ...
├── l10n.yaml                     # konfigurasi lokalisasi
├── android_res_extra/            # ikon notifikasi yang dimasukkan ke APK oleh CI
├── .github/
│   └── workflows/
│       ├── build-apk.yml         # CI: build APK di setiap push ke main
│       └── build.yml             # CI: build APK + draf rilis GitHub
├── pubspec.yaml
├── LICENSE
├── README.md                     # dokumentasi utama (Inggris)
└── README.id.md                  # dokumentasi (Bahasa Indonesia)
```

---

## Pengembangan

### Menambah string baru untuk pengguna

1. Tambahkan key ke `lib/l10n/app_en.arb` (Inggris) dan `lib/l10n/app_id.arb` (Indonesia)
2. Jalankan `flutter gen-l10n`
3. Gunakan lewat `AppLocalizations.of(context)!.yourKey`

> [!WARNING]
> File di dalam `lib/l10n/gen/` dihasilkan otomatis. Jangan diedit manual, ubah file `.arb` lalu jalankan `flutter gen-l10n`.

---

## Pengujian

Verifikasi sebelum setiap push, keduanya harus bersih:

```bash
flutter analyze
flutter test
```

| Pemeriksaan | Syarat |
|-------------|--------|
| `flutter analyze` | Harus melaporkan **No issues found** (nol error, nol warning) |
| `flutter test` | Seluruh suite harus lulus |

Lint ditegakkan lewat `analysis_options.yaml` (flutter_lints plus `prefer_single_quotes` dan `sort_child_properties_last`).

---

## Continuous Integration

| Workflow | Fungsi |
|----------|--------|
| `build-apk.yml` | Build APK di setiap push ke main |
| `build.yml` | Build APK dan buat draf rilis GitHub |

Ikon notifikasi dari `android_res_extra/` dimasukkan ke APK oleh CI.

---

## FAQ

<details>
<summary><b>Musik berhenti saat aplikasi masuk ke latar belakang?</b></summary>

Pastikan optimasi baterai dimatikan untuk Swara (Autostart / latar belakang tanpa batas di XOS, MIUI, dan skin sejenis), dan izin notifikasi sudah diberikan.

</details>

<details>
<summary><b>Beberapa lagu menampilkan "Unknown Artist" atau tidak punya lirik?</b></summary>

Pengambilan otomatis bergantung pada database publik (iTunes, lrclib, lyrics.ovh). Lagu lokal atau indie sering tidak ada di sana. Gunakan Edit Metadata / Edit Lyrics pada lagu untuk memperbaikinya secara manual.

</details>

<details>
<summary><b>Bagaimana cara mengganti bahasa?</b></summary>

Pengaturan, bagian **Bahasa**, pilih English atau Bahasa Indonesia. Bahasa Inggris adalah default.

</details>

---

## Penulis

<div align="center">

| [![Nicolas Dwi Dharma](https://github.com/github.png?size=100)](https://github.com/nekonaru) |
|:---:|
| **Nicolas Dwi Dharma** |
| [github.com/nekonaru](https://github.com/nekonaru) |

</div>

---

## Disclaimer

Swara adalah proyek open-source independen dan tidak berafiliasi dengan atau didukung oleh Apple, lrclib, lyrics.ovh, atau Google. Metadata dan lirik berasal dari database publik dan bisa saja tidak lengkap atau kurang akurat, itulah mengapa setiap lagu bisa diedit secara manual.

---

## Lisensi

Didistribusikan di bawah **Lisensi MIT**. Lihat [`LICENSE`](LICENSE) untuk informasi lebih lanjut.
