# Changelog

## v3.3.0

Rilis performa: aplikasi kini merender daftar dan artwork layaknya pemutar native, dan proyek mengikuti satu proses rilis yang sama.

## Fitur baru

- **Daftar dan artwork sehalus native.** Daftar library, pencarian, dan dashboard kini mendekode artwork sesuai ukuran tampilan, melewatkan pekerjaan layout per frame, dan hanya menggambar ulang bagian yang berubah, sehingga gulir tetap lancar di library besar.

## Peningkatan

- **Body rilis diambil dari file ini.** Rilis yang dibuat workflow build kini mencantumkan changelog ini, bukan catatan yang dikode mati, dan judul rilis adalah `Swara vX.Y.Z`.
- **Proyek Android dikomit.** Folder `android/` kini menjadi bagian dari repository, bukan diregenerasi dan di-patch CI di setiap build, jadi build reproducible dan workflow lebih pendek.

## Perbaikan bug

- **Avatar penulis di README salah.** Bagian Author kini menautkan avatar dan profil penulis yang benar.

## v3.2.0

Satu tema terpusat, sampul yang melayang ke player.

## Fitur baru

- **Satu sistem desain untuk seluruh aplikasi.** File baru `lib/theme/app_theme.dart` menentukan app bar, kartu, dialog, baris daftar, tombol, snackbar, tab, pembatas, bottom sheet, dan transisi halaman di satu tempat. Tema terang dan gelap sama-sama dibangun oleh fungsi yang sama, jadi keduanya tidak lagi bisa berbeda satu sama lain.
- **Sampul melayang ke player.** Mengetuk mini player membesarkan sampul kecilnya menjadi sampul besar di layar player, alih-alih bertukar dua gambar yang tidak berhubungan.
- **Satu transisi halaman untuk semua.** Layar terbuka dengan fade pendek dan geser ke atas kecil alih-alih zoom bawaan, dan player tetap punya gerakannya sendiri dari bawah.

## Peningkatan

- **Teks redup mengikuti tema.** Tujuh puluh warna abu-abu teks dan ikon yang ditulis tetap di lima belas file kini memakai warna sekunder tema, jadi menyesuaikan dengan latar terang, gelap, dan AMOLED serta warna aksen pilihanmu.
- **Snackbar melayang secara bawaan.** Snackbar tidak lagi menempel di tepi bawah hanya karena sebuah layar lupa meminta perilaku melayang.
- **Tab library menyatu dengan aplikasi.** Label terpilih dan tidak terpilih, serta garis tipis di bawah tab, kini datang dari tema alih-alih bawaan Material.
- **Bar progres mengikuti aksen.** Jalur pemuat dulu tetap ungu bawaan saat aksenmu teal atau oranye; kini memakai warna temamu.

## Perbaikan bug

- **Tiga abu-abu berbeda untuk jenis teks yang sama kini hilang.** Subjudul bisa terbaca di satu layar dan nyaris tak terlihat di layar berikutnya, terutama di latar hitam AMOLED; semuanya kini memakai satu warna bertema.
- **Dialog, sheet, dan baris selalu satu bentuk.** Sudut yang digayakan per layar membuat popup sejenis terlihat berbeda tergantung dari mana ia terbuka.

## v3.1.0

Pemindaian metadata hanya manual, dan setiap pemindaian bisa dihentikan.

## Fitur baru

- **Pemindaian metadata hanya manual.** Pemindaian metadata tidak lagi mulai sendiri, dan setiap pemindaian bisa dihentikan di tengah jalan tanpa kehilangan apa pun.

## v3.0.0

Rilis hardening keamanan.

## Peningkatan

- **adb backup dinonaktifkan.** Database lokal, favorit, dan riwayat dengar tidak lagi bisa diambil dari ponsel dengan `adb backup`.
- **Dependensi diperbarui.** Semua dependensi dipindah ke versi kompatibel terbaru.

## Rilis sebelumnya

v2.9.x ke bawah tercantum di halaman Releases GitHub. Sorotan dari versi itu: daftar penuh tanpa tombol Load more, lompat A-Z instan, pencarian tahan typo dengan saran "did you mean", pencarian dan pemindaian di luar UI thread, regex yang diangkat dan turunan yang di-cache, satu permintaan lrclib untuk lirik polos dan tersinkron, perbaikan shortcut pengaturan, serta perbaikan crash untuk lagu tanpa path file.
