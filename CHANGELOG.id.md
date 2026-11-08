# Changelog

## v3.3.0

Rilis performa: daftar dan artwork kini tampil semulus pemutar native, dan proyek mengikuti satu proses rilis yang sama.

## Fitur baru

- **Daftar sehalus native.** Daftar library, pencarian, dan dashboard kini mendekode artwork sesuai ukuran tampilan, melewatkan pekerjaan layout per frame, dan hanya menggambar ulang bagian yang berubah, sehingga gulir tetap lancar di library besar.

## Peningkatan

- **Body rilis diambil dari changelog.** Rilis yang dibuat workflow build kini mencantumkan changelog, bukan catatan yang dikode mati, dan judul rilis adalah `Swara vX.Y.Z`.
- **Proyek Android dikomit.** Folder `android/` kini menjadi bagian dari repository, bukan diregenerasi dan di-patch CI di setiap build, jadi build reproducible dan workflow lebih pendek.

## Perbaikan bug

- **Avatar penulis salah.** Bagian Author di README kini menautkan avatar dan profil penulis yang benar.

## v3.2.0

Satu tema terpusat untuk seluruh aplikasi, sampul yang terbang dari mini player ke player, dan satu transisi halus yang sama di semua halaman.

## Fitur baru

- **Satu sistem desain.** File baru `lib/theme/app_theme.dart` menentukan app bar, kartu, dialog, baris daftar, tombol, snackbar, tab, pembatas, bottom sheet, dan transisi halaman di satu tempat; tema terang dan gelap sama-sama dibangun oleh fungsi yang sama, jadi keduanya tidak lagi bisa berbeda.
- **Sampul terbang ke player.** Mengetuk mini player membesarkan sampul kecilnya menjadi sampul besar di layar player, alih-alih bertukar dua gambar yang tidak berhubungan.
- **Satu transisi di mana-mana.** Layar terbuka dengan fade pendek dan geser ke atas kecil alih-alih zoom bawaan, dan player tetap punya gerakannya sendiri dari bawah.

## Peningkatan

- **Teks redup mengikuti tema.** Tujuh puluh warna abu-abu teks dan ikon yang ditulis tetap di lima belas file kini memakai warna sekunder tema, jadi menyesuaikan dengan latar terang, gelap, dan AMOLED serta warna aksen pilihanmu.
- **Snackbar mengambang.** Snackbar tidak lagi menempel di tepi bawah hanya karena sebuah layar lupa meminta perilaku mengambang.
- **Tab library menyatu.** Label terpilih dan tidak terpilih, serta garis tipis di bawah tab, kini datang dari tema alih-alih bawaan Material.
- **Bar progres mengikuti aksen.** Jalur pemuat dulu tetap ungu bawaan saat aksenmu teal atau oranye; kini memakai warna temamu.

## Perbaikan bug

- **Satu abu-abu redup.** Tiga abu-abu berbeda untuk jenis teks yang sama kini hilang; semuanya memakai satu warna bertema yang, khususnya di latar hitam AMOLED, tetap terbaca.
- **Satu bentuk.** Dialog, sheet, dan baris selalu satu bentuk; sudut yang digayakan per layar membuat popup sejenis terlihat berbeda tergantung dari mana ia terbuka.

## v3.1.0

Scan metadata kini hanya berjalan saat kamu memulainya sendiri, dan bisa dihentikan kapan pun tanpa kehilangan pekerjaan yang sudah diambil.

## Fitur baru

- **Scan metadata manual.** Scan metadata tidak pernah jalan sendiri; dulu aplikasi menyalakan pengambilan metadata di latar belakang beberapa detik setelah dibuka, diam-diam memakai kuota internet dan jatah rate limit iTunes untuk lagu yang sedang tidak kamu lihat, dan mulai sekarang scan hanya jalan saat kamu menjalankannya sendiri dari menu library, Settings, atau layar folder.
- **Scan bisa dihentikan.** Setiap scan bisa dihentikan, dengan kontrol berhenti di mana pun scan sedang berjalan: header library, tile Settings, layar cover hilang, layar lirik hilang, dan layar folder; batch yang sedang berjalan diselesaikan dan semua yang sudah diambil tetap disimpan, jadi menghentikan scan tidak pernah membuang hasil yang sudah didapat.
- **Notifikasi penghentian.** Saat scan berakhir lebih awal karena kamu menghentikannya, aplikasi menyebut scan-nya dihentikan dan semua yang sudah diambil tetap ada, alih-alih melaporkan seluruh pekerjaan sebagai selesai.

## Peningkatan

- **Startup lebih ringan.** Pengambilan metadata otomatis di latar belakang yang berjalan lima detik setelah aplikasi dibuka kini dihapus, jadi membuka Swara tidak lagi memulai permintaan jaringan dengan sendirinya; musik tetap langsung muncul dari basis data lokal, dan pemindaian berkas lokal yang menjaga lagu baru tetap terlihat tidak berubah.
- **Verifikasi.** 201 test lolos, termasuk guard baru yang gagal jika ada layar yang menjalankan scan metadata sendiri atau jika kontrol berhenti dihapus; flutter analyze: no issues; README Inggris dan Indonesia diperbarui untuk mencerminkan perilaku manual ini.

## Perbaikan bug

- **Progres scan folder akurat.** Progres scan folder kini mengikuti pekerjaan yang sebenarnya; dulu dihitung terhadap semua lagu dalam folder meski yang diproses hanya lagu yang belum discan, sehingga bisa tersendat sebelum penuh, dan kini memakai jumlah target yang benar.

## v3.0.0

Rilis hardening besar tanpa layar baru: lebih aman dipasang, lebih ringan dari dependensi lama, dan sudah melewati audit keamanan yang bersih.

## Peningkatan

- **Backup dimatikan.** Library lokal kamu tidak bisa lagi ditarik keluar dari HP lewat adb; manifest Android dulu mengizinkan backup secara bawaan, yang berarti siapa pun dengan akses fisik dan USB debugging bisa mengekstrak seluruh basis data SQLite (library, favorit, dan riwayat dengar lengkapmu) dengan satu perintah, dan backup kini dimatikan termasuk backup cloud dan transfer antar perangkat, karena Swara tidak punya akun dan tidak ada yang layak diekspor.
- **Audit keamanan bersih.** Audit keamanan menyeluruh atas kode bersih di titik yang penting; riwayat Git selama 133 commit tidak memuat kunci API atau token yang bocor, setiap panggilan eksternal (iTunes, lrclib, lyrics.ovh) sudah memakai HTTPS dan tidak pernah HTTP polos, dan seluruh akses basis data memakai parameterized query alih-alih konkatenasi string sehingga tidak ada jalur SQL injection, dengan riwayat dengar, playlist, dan cache metadata semuanya diperiksa.
- **Hardening tercetak sendiri.** Build kini mencetak hardening-nya sendiri, dan pipeline CI menampilkan manifest yang sudah diperkuat di setiap run, jadi regresi akan terlihat di log build alih-alih terkirim diam-diam.
- **Dependensi diperbarui.** Enam dependensi diperbarui dalam rentang amannya, termasuk lapisan basis data (sqflite 2.4.5), pemilih berkas, penyimpanan preferensi, dan pengelola cache, yaitu pustaka yang berjalan di setiap pemindaian dan setiap pemuatan layar.
- **R8 sengaja tidak diaktifkan.** Minifikasi R8 penuh sengaja tidak diaktifkan; flag obfuscation Flutter hanya menutupi kode Dart, dan menyalakan minifikasi penuh akan membuat R8 ikut memangkas kelas native yang dicapai plugin seperti on_audio_query lewat refleksi dan JNI, yang membuat crash di HP fisik dan tidak di tempat lain, jadi APK tetap ramping lewat obfuscation dan pemisahan per arsitektur alih-alih mempertaruhkan ukuran yang dihemat.
- **Verifikasi.** 196 test lolos, tidak berubah setelah pembaruan dependensi; flutter analyze: no issues; manifest yang sudah diperkuat dicetak di setiap run CI.

## Perbaikan bug

- **Tanpa perubahan fungsional.** Perbaikan pemindaian dan lirik dari v2.9.10 sampai v2.9.13 semuanya sudah termasuk di build ini.

## v2.9.13

Lirik sinkron dan lirik biasa kini datang dari satu pencarian lrclib dalam satu permintaan.

## Fitur baru

- **Satu pencarian lrclib.** Lirik sinkron dan lirik biasa kini datang dari satu permintaan lrclib, karena lrclib mengembalikan kedua bentuk itu dalam satu respons, bukan dua permintaan terpisah ke dua layanan berbeda.
- **Lirik sinkron tetap tampil.** Saat sebuah sumber hanya menyediakan bentuk ber-timestamp, aplikasi membuang timestamp-nya untuk membangun tampilan biasa, sehingga panel lirik tidak pernah kosong.
- **Lirik sinkron untuk cache.** Pencarian lrclib kini melengkapi tampilan sinkron untuk lagu yang sudah ada di cache, jadi entri lama tidak terjebak tanpa lirik bergulir.

## Peningkatan

- **Setengah permintaan lirik.** Satu permintaan jaringan menggantikan dua per lagu, karena lrclib sendiri kini melayani keduanya, yang memangkas separuh permintaan saat pemindaian metadata.
- **Lirik di thread latar.** Seluruh pengambilan lirik via HTTP kini berjalan di luar thread utama; pencarian lrclib pindah ke isolate latar belakang seperti lyrics.ovh, jadi pemindaian atau pengambilan lirik tidak lagi membekukan antarmuka, dan klien HTTP bersama yang dulu duduk di thread utama kini hilang karena setiap permintaan punya klien sendiri di dalam isolate-nya.
- **Verifikasi.** 196 test lolos, termasuk guard baru yang mengunci satu permintaan dan urutan cadangan; flutter analyze: no issues.

## Perbaikan bug

- **Penyimpanan lirik atomik.** Kegagalan pengambilan lirik tidak lagi membuat lagu setengah jadi, karena jalur biasa dan jalur sinkron kini berbagi satu helper penyimpanan ber-batas, sehingga sebuah payload tidak pernah tertulis tanpa batas dan kegagalan tulis cache tidak lagi mengganggu pengambilan yang sudah berhasil.
- **lyrics.ovh hanya cadangan.** lyrics.ovh tetap hanya sebagai cadangan dan ditanyakan saat lrclib tidak punya entri untuk sebuah lagu, yang menjaga lagu yang belum tercakup lrclib tetap berfungsi alih-alih kehilangan lirik.

## v2.9.12

Scan diperbaiki setelah ketidakcocokan tipe membuatnya gagal untuk semua lagu.

## Peningkatan

- **Verifikasi.** 191 test lolos, termasuk guard baru untuk ketidakcocokan tipe isolate; flutter analyze: no issues.

## Perbaikan bug

- **Scan berfungsi lagi.** Scanner latar belakang mengirim kerjanya ke isolate terpisah, dan salah satu nilai yang menyeberang batas itu berupa daftar folder yang dikecualikan yang dibaca kembali sebagai list padahal aslinya sebuah set; ketidakcocokan tipe melempar error sebelum satu lagu pun diperiksa, sehingga library tetap kosong meski izin sudah diberikan dan musik ada di HP, dan nilai itu kini diubah bentuknya alih-alih di-cast sementara pengirim mengirim list biasa yang tidak ambigu.
- **Kegagalan nilai terisolasi.** Nilai yang tidak terduga tidak lagi menjatuhkan seluruh scan, karena scanner merendahkan nilai daftar-folder-kecualikan yang tak terduga menjadi set kosong, jadi ketidakcocokan hanya mengorbankan filter folder, bukan semua lagu.
- **Guard test ditambahkan.** Guard test kini mengunci kegagalan yang persis sama dengan memeriksa cast yang membuat scan gagal, sehingga ia tidak bisa kembali diam-diam.

## v2.9.11

Jalan pintas "Buka Pengaturan" kini andal muncul saat izin musik ditolak, lanjutan fokus dari v2.9.10 hanya dengan perubahan kebenaran.

## Peningkatan

- **Verifikasi.** 188 test lolos, termasuk guard baris rusak yang menjaga satu lagu buruk tidak mengosongkan seluruh library; flutter analyze: no issues.

## Perbaikan bug

- **Buka Pengaturan andal.** Tombol "Buka Pengaturan" di layar "Belum ada musik" kini benar-benar muncul saat akses musik ditolak; dulu keputusannya bergantung pada pencocokan teks di dalam pesan error yang bisa gagal diam-diam, dan aplikasi kini melacak penolakan itu secara eksplisit sehingga jalan pintasnya muncul secara andal.
- **Cek dua izin.** Penolakan izin kini diperiksa di izin audio maupun izin penyimpanan lama, yang diandalkan perangkat lama yang jatuh ke penyimpanan; dulu perangkat itu melaporkan status yang salah sehingga jalan pintasnya tidak pernah muncul.
- **Cek izin anti-crash.** Pemeriksaan izin tidak lagi bisa membuat scan gagal karena punya guard-nya sendiri, sehingga kegagalan di sana hanya merendah ke pesan biasa alih-alih kehilangan hasil scan sepenuhnya.

## v2.9.10

Deteksi musik diperbaiki sehingga library tidak lagi kosong meski izin penyimpanan sudah diberikan, hanya perubahan kebenaran dan diagnosa.

## Peningkatan

- **Verifikasi.** 188 test lolos, termasuk guard baru yang mengunci penanganan baris rusak; flutter analyze: no issues.

## Perbaikan bug

- **Library blank diperbaiki.** Satu lagu dengan path file kosong (yang bisa dilaporkan MediaStore di scoped storage) dulu membuat seluruh pemuatan gagal dan lagu lain ikut hilang; loader kini melewati baris itu alih-alih menjatuhkan seluruh library.
- **Path kosong disaring.** Scanner dulu langsung menyisipkan lagu tanpa path file ke database, dan itu pemicu bug library blank; lagu seperti itu kini disaring saat pemindaian di thread terpisah.
- **Scan gagal menjelaskan diri.** Layar "Belum ada musik" dulu menyembunyikan alasan scan menemukan nol lagu; kini ia menampilkan errornya, dan kalau izin musik ditolak permanen ia menawarkan tombol langsung ke pengaturan aplikasi.

## v2.9.9

Gerbang lint permanen dan guard context async yang lebih ketat, tanpa mengubah apa yang kamu lihat dan dengar.

## Peningkatan

- **Gerbang analyzer permanen.** Proyek kini mengaktifkan flutter_lints plus prefer_single_quotes dan sort_child_properties_last lewat analysis_options.yaml baru, sehingga masalah gaya dan kebenaran ketahuan sebelum rilis di setiap perubahan.
- **Verifikasi.** 185 test lolos dan flutter analyze: no issues, kini ditegakkan oleh analysis_options.yaml yang di-commit.

## Perbaikan bug

- **Guard mounted ditambahkan.** Empat belas lokasi context setelah await kini punya guard mounted yang benar, jadi snackbar, dialog, dan navigasi setelah jeda async memastikan widget masih hidup, menghilangkan satu kelas crash laten saat layar ditutup sementara kerja masih berjalan.
- **Temuan lint diselesaikan.** Empat puluh dua temuan lint di seluruh kode sudah diperbaiki, sebagian besar const constructor, quote tunggal, rename local yang menimpa, dan komentar yang di-hoist; tidak ada yang mengubah perilaku runtime.

## v2.9.8

Rilisan pemangkasan beban murni tanpa fitur baru dan tanpa perubahan perilaku, meringankan kerja saat scroll dan cari.

## Peningkatan

- **Normalisasi pencarian di-cache.** Normalisasi pencarian kini berjalan sekali per baris dan sekali per query, dan pass toleran salah ketik tidak lagi membangun regex ulang atau menormalisasi query untuk setiap lagu, sehingga beban per ketukan berkurang separuh.
- **View playlist di-cache.** Layar detail playlist mengurutkan dan menyaring sekali saja, bukan sekali per rebuild, dengan view terurut dan total durasinya di-cache per daftar sumber, mode sort, dan query, sehingga update keyboard, favorit, dan pemutaran tidak lagi mengurutkan ulang seluruh playlist.
- **Sort pakai code unit.** Sort membandingkan code unit, bukan regular expression, dan cek tingkat sort judul yang dulu memakai regex per perbandingan kini langsung membaca rentang ASCII karakter pertama.
- **Daftar terfilter di-cache.** Favorit serta daftar artwork dan lirik yang hilang di-cache per versi pustaka, jadi layar-layar itu tidak lagi membangun ulang daftar tersaring di setiap notifikasi progres pemindaian.
- **Sentuhan art cache dibatasi.** Cache artwork memperbarui timestamp file paling sering tiap 10 menit per cover, bukan lagi satu panggilan filesystem per tile hanya untuk menjaga urutan cache.
- **Regex scan di-hoist.** Parsing nama file hasil pemindaian dan grouping duplikat meng-hoist regex-nya, sehingga pemindaian penuh tidak lagi mengkompilasi pola per file.
- **Verifikasi.** 185 test lolos, termasuk guard baru yang mengunci regex yang di-hoist, view playlist dan daftar favorit yang di-cache, serta sentuhan art cache yang di-throttle; flutter analyze: no issues.

## Perbaikan bug

- **Tanpa perubahan perilaku.** Semua optimasi di rilis ini bersifat internal; hasil pencarian, urutan sort, favorit, serta daftar artwork dan lirik yang hilang tetap berperilaku persis seperti sebelumnya.

## v2.9.7

Rilisan pemangkasan beban murni tanpa fitur baru, meringankan search, sort, dan update baris.

## Peningkatan

- **Matching pencarian di isolate.** Fuzzy match dan pass salah ketik pindah ke isolate latar, jadi tidak lagi berjalan di frame saat kamu mengetik, dan teks per lagunya dibangun sekali per versi pustaka alih-alih setiap ketukan.
- **Update satu baris.** Favorit, rename, dan refresh metadata satu lagu kini menambal baris itu di memori alih-alih query ulang, sort ulang, dan membangun ulang semua konsumen.
- **Pemutar berbasis indeks.** Layar pemutar mencari lagu yang diputar lewat indeks, bukan memindai seluruh pustaka di setiap notifikasi pemutaran.
- **Sort dihitung sekali.** Key sort dihitung sekali per lagu, jadi sort tidak lagi mengecilkan kedua sisi di dalam setiap perbandingan, yang dulu mengalokasikan ratusan ribu string per pemuatan.
- **Verifikasi.** 178 test lolos, termasuk guard baru yang mengunci jalur isolate untuk pencarian, tambal baris di memori, dan lookup indeks; flutter analyze: no issues.

## Perbaikan bug

- **Favorit tetap sinkron.** Perubahan favorit kini menaikkan versi pustaka yang menjadi gate daftar favorit, menjaga layar Favorit tetap sinkron dengan update in-memory yang lebih ringan.

## v2.9.6

Scan lebih cepat dan refresh metadata per lagu.

## Fitur baru

- **Refresh satu lagu.** Menu lagu kini punya aksi "Scan metadata" yang mengambil judul, cover, genre, dan lirik untuk satu lagu itu saja tanpa menyentuh pustaka lain.

## Peningkatan

- **Scan di thread latar.** Cek folder, fallback judul, dan penyiapan tulisan kini berjalan di isolate latar, jadi UI tetap responsif saat ribuan lagu discan.
- **Lookup di thread latar.** Lookup iTunes dan lirik tidak lagi berjalan di thread utama, jadi pengambilan metadata tidak lagi memblokir frame saat scan massal.
- **Startup lebih ringan.** Pass metadata latar mulai 5 detik setelah frame pertama, bukan berjalan inline.
- **Verifikasi.** 169 test lolos dan flutter analyze: no issues.

## Perbaikan bug

- **Error build diperbaiki.** Guard `mounted` yang hilang membuat build CI gagal.
- **Perlindungan captive portal.** Hanya jawaban yang benar-benar terlihat seperti iTunes atau lyrics.ovh yang disimpan sebagai miss "tidak ditemukan", sedangkan halaman HTML, respons 5xx, dan kejutan lain tetap bisa dicoba ulang alih-alih mengunci lagu selama 90 hari.
- **Kecualian folder tersembunyi.** Kecualian folder tersembunyi berperilaku persis seperti sebelumnya di jalur isolate baru, termasuk path bergaya Windows.
- **Test lintas line ending.** Guard pemeriksaan sumber tidak lagi bergantung pada line ending, jadi lolos di checkout Windows juga.

## v2.9.5

Scrolling lebih ringan untuk pustaka besar dan teks default lebih kecil.

## Peningkatan

- **Scrolling pustaka lebih mulus.** Scroll listener tidak lagi memanggil `setState` di setiap fling, jadi scrolling pustaka besar tidak lagi membekukan atau mengganggu penanganan gesture di daftar dengan ribuan lagu.
- **Teks default lebih kecil.** Aplikasi dibuka dengan skala teks default 0.85 sehingga lebih banyak baris muat di layar tanpa scroll.
- **Pencarian cover di memori.** Indeks cover dibangun sekali saat startup, jadi scrolling tidak lagi menyentuh disk per frame.
- **Verifikasi.** 169 test lolos dan flutter analyze: no issues.

## v2.9.4

Rilis stabilitas: pembacaan database tidak lagi crash pada baris yang korup.

## Perbaikan bug

- **Cast data korup.** Cast `as int` tanpa guard pada data database yang korup menyebabkan crash di tujuh tempat; kini dijaga sehingga baris korup dilewati, bukan crash.

## v2.9.3

Rilis perbaikan keamanan: temuan audit keamanan diperbaiki, termasuk URL injection, validasi content-type, dan path traversal.

## Peningkatan

- **Perbaikan audit.** URL injection diblokir, cover yang diunduh diverifikasi dari content-type-nya, dan path traversal di restore backup ditolak.

## v2.9.2

Memperbaiki streak pendengaran yang putus di malam pergantian DST, 404 captive portal yang mengunci lagu sebagai tidak ditemukan, dan dashboard yang mengabaikan folder tersembunyi.

## Peningkatan

- **Verifikasi.** 169 test lolos dan flutter analyze: no issues.

## Perbaikan bug

- **Streak DST diperbaiki.** Perhitungan streak memakai pengurangan 24 jam, yang bisa jatuh di jam 23 pada malam pergantian daylight saving time dan memotong streak satu hari lebih awal.
- **404 captive portal.** Captive portal (WiFi hotel, bandara, kampus) bisa mengembalikan 404 dengan body HTML untuk URL iTunes, yang dulu diperlakukan sebagai hasil "lagu tidak ada di iTunes" yang definitif dan mengunci metadata setiap lagu yang terdampak sebagai tidak tersedia selama 90 hari; kini hanya respons yang benar-benar terlihat seperti iTunes yang dicatat sebagai miss.
- **Folder tersembunyi di dashboard.** Lagu dari folder tersembunyi dulu masih ikut dihitung, ditampilkan di "belum pernah diputar", dan "putar semua" akan memulai lagu yang sengaja disembunyikan; dashboard kini menghormati folder tersembunyi.

## v2.9.1

Rilis stabilitas: crash saat startup, pengaturan yang tidak tersimpan, dan lagu yang hilang setelah scan kini diperbaiki.

## Perbaikan bug

- **Crash saat startup.** Perbaiki crash yang terjadi saat membuka aplikasi.
- **Pengaturan tersimpan.** Pengaturan kini tersimpan dengan benar.
- **Lagu hilang.** Lagu yang hilang setelah scan kini terdeteksi.

## v2.9.0

Pencarian yang memaafkan salah ketik, sehingga salah ketik kecil tetap menemukan lagu yang benar.

## Fitur baru

- **Pencarian tahan salah ketik.** Pencarian kini memaafkan huruf tertukar dan kesalahan tunggal, jadi "fadde" atau "wlaeker" menemukan "Faded" dan "Walker", dengan hasil yang cocok persis selalu didahulukan agar tebakan yang hanya mirip tidak bisa mendorong lagu yang benar-benar kamu ketik ke bawah daftar.
- **Saran ejaan saat kosong.** Jika pencarian tidak mengembalikan apa pun dan ada kata yang mirip, layar kosong menawarkan kata itu sebagai saran satu ketukan.

## Peningkatan

- **Kata pendek persis.** Kata empat huruf atau lebih pendek dicocokkan persis, karena satu kesalahan saja akan cocok dengan hampir seluruh kamus.
- **Batas kesalahan per panjang.** Kata lima dan enam huruf boleh satu kesalahan, dan kata tujuh huruf atau lebih boleh dua.
- **Huruf tertukar dihitung satu.** Huruf yang tertukar dihitung sebagai satu kesalahan, sedangkan Levenshtein biasa menghitungnya dua dan memaksa toleransi yang terlalu longgar sampai pencarian tidak berguna.
- **Batas dua kesalahan.** Lebih dari dua kesalahan tidak ditebak, karena saran yang salah lebih buruk daripada tidak ada saran, dan hasil yang salah lebih buruk daripada tidak ada hasil.
- **Verifikasi.** 169 test lolos, termasuk suite khusus untuk jarak edit, aturan toleransi, dan logika saran.

## v2.8.0

Rilis ini menghadirkan kontrol waktu lirik, equalizer lebih halus, dan dashboard lebih tenang.

## Fitur baru

- **Kontrol waktu lirik.** Lirik sinkron sekarang membaca tag offset standar dari file .lrc, yang dipakai banyak lagu, plus dua tombol untuk menggeser lirik 100 ms ke arah mana pun; koreksinya kembali ke nol saat lagu berganti, karena pengaturan waktu yang disetel untuk satu lagu tidak berarti apa-apa di lagu berikutnya.

## Perbaikan bug

- **Lirik panjang scroll.** Lirik panjang sekarang ikut bergulir ke baris aktif: highlight bisa berubah sementara teks yang terlihat membeku, semakin sering semakin panjang liriknya, karena baris di luar viewport tidak pernah dibangun.
- **Slider EQ stabil.** Slider equalizer tidak lagi melawan dirinya sendiri: menggeser satu band memicu puluhan tulisan yang saling menimpa dan gambar ulang tiap pixel, sehingga kurva bisa berhenti di campuran nilai.
- **Status EQ jujur.** Equalizer memberi tahu apakah ia bekerja: Pengaturan kini menampilkan EQ aktif atau EQ tidak tersedia di perangkat ini, bukan berpura-pura.
- **Acak ingat riwayat.** Acak pintar ingat lagu yang belum kamu dengar lama: setelah tiap app ditutup, separuh peringkat ini mati sehingga semua lagu terlihat sama-sama lama tidak diputar.
- **Notifikasi stabil.** Notifikasi tidak lagi bisa beku selamanya: permintaan stop dari Android atau headset dulu melepas handler untuk sisa sesi, setelah itu judul, posisi, dan tombol acak berhenti bergerak.
- **Hitungan dashboard akurat.** Hitungan dashboard kini sesuai dengan yang kamu lihat: lagu dari folder tersembunyi masih ikut dihitung, ditampilkan, dan bisa diputar, sehingga dashboard bisa mengklaim lebih banyak lagu daripada yang library perlihatkan.
- **Pindah playlist jelas.** Memindahkan playlist ke folder tidak lagi bisa gagal diam-diam: perpindahan yang gagal dulu menutup dialog tanpa pesan apa pun.
- **Pengaturan tersimpan.** Pengaturan selalu tersimpan: dua ketukan cepat bisa membuat nilai tersimpan tidak sesuai dengan layar sampai app ditutup.

## Peningkatan

- **Cover di luar thread.** Cover playlist dibuat di luar thread utama: menggabungkan empat gambar resolusi penuh di UI isolate membekukan app beberapa detik, dan cache lama hanya membandingkan jumlah lagu sehingga lagu yang tertukar memakai cover basi.
- **Cover di memori.** Pencarian cover hanya di memori, diindeks sekali saat app mulai.
- **Collage atomik.** Penulisan collage bersifat atomik, jadi proses yang mati di tengah tidak lagi meninggalkan cover setengah jadi yang terbaca utuh.
- **139 test.** 139 test mencakup parsing offset lirik, serialisasi equalizer, pelepasan handler, sidik jari collage, dan filter folder dashboard.

## v2.7.1

Crossfade dan equalizer akhirnya bekerja di rilis ini.

## Perbaikan bug

- **Transisi mulus.** Crossfade tidak lagi rusak di setiap transisi: lagu yang selesai memunculkan event penyelesaian normal di tengah fade-nya sendiri, yang memicu lagu berikutnya, membatalkan fade, dan memulai ulang lagu yang sedang masuk dari detik nol, sehingga yang terdengar adalah lompatan bunyi, bukan transisi halus; sekarang handler penyelesaian menyingkir selagi fade berjalan.
- **Equalizer berfungsi.** Equalizer sekarang benar-benar mengubah suara: plugin audio tidak pernah menjawab perintahnya sendiri, jadi setiap perubahan preset dan slider kehabisan waktu dan tidak ada gain yang sampai ke output; sekarang perintah dikirim tanpa menunggu, kesiapan dikonfirmasi lewat panggilan yang benar-benar menjawab, dan level band dikirim dalam dB tanpa dikali dua, yang membuat HP kamu diminta +40 dB, di luar rentang yang diizinkan.
- **Repeat one bersih.** Repeat one tidak lagi menyisakan suara kedua: saat ada crossfade, player lain tetap memutar lagu yang sedang fade dengan suara pelan di belakang.
- **Duplikat lebih akurat.** Pencari duplikat tidak lagi menghapus rekaman berbeda: versi studio dan versi live lagu yang sama dianggap duplikat, dan hapus semua duplikat menghapus versi live beserta anggota playlist dan riwayatnya; album dan durasi kini ikut dicocokkan, dan setiap penghapusan diperiksa.
- **Daily Mix responsif.** Daily Mix dan Unplayed mengikuti perubahanmu: menyembunyikan folder atau scan ulang kini memperbaruinya, bukan tetap memuat lagu tersembunyi sampai app ditutup.
- **Folder tersembunyi dihormati.** Most Played menghormati folder tersembunyi: lagu dari folder yang kamu sembunyikan tidak lagi muncul dan bisa diputar di sana.
- **Loop A-B bertahan.** Pasang loop A-B saat crossfade jalan sekarang bertahan, bukan hilang sedetik kemudian.
- **Tanpa akses disk.** Cover album tidak lagi menyentuh disk saat scrolling, karena pencarian cover berjalan di setiap rebuild tiap baris.

## Peningkatan

- **Edit massal satu batch.** Edit massal satu batch, bukan satu muat ulang per lagu: mengedit 500 lagu sebelumnya memuat ulang seluruh pustaka 500 kali dan membuat app beku.
- **Cover di memori.** Pencarian cover hanya di memori, dengan satu indeks yang dibangun saat app mulai.
- **127 test.** 127 test mencakup regression test baru untuk balapan crossfade, satuan equalizer, pencocokan duplikat, batch edit massal, dan penanganan folder tersembunyi.

## v2.7.0

Rilis ini menghentikan scan yang menghapus metadata kamu.

## Perbaikan bug

- **Metadata aman.** Scan ulang tidak lagi menghapus metadata hasil enrich: setiap scan device menulis ulang lagu yang sudah dikenal sebagai baris baru yang hanya berisi tag dari file, dan SQLite REPLACE menghapus baris lama sebelum insert, sehingga setiap tarik ke bawah untuk refresh dan setiap scan otomatis saat app dibuka menghapus album cover, genre, region, dan lirik hasil enrich plus mengundo edit metadata manual; sekarang lagu yang sudah ada hanya menerima fakta yang benar-benar berasal dari file, seperti path dan durasinya.
- **Tidak ada balapan scan.** Dua scan yang tumpang tindih tidak lagi bisa menghapus lagu yang baru ditambahkan: dua scan yang jalan bersamaan membandingkan tabel lagu dengan snapshot device masing-masing, sehingga scan yang lebih lambat menghapus lagu yang baru saja di-insert scan yang lebih cepat beserta anggota playlist dan riwayat listenednya; scan kedua sekarang diabaikan selama satu berjalan, dan pembersihan memakai snapshot yang diambil sebelum scan dimulai.
- **Ambil dari internet menyimpan.** Ambil dari internet sekarang benar-benar menyimpan: di Edit Metadata tombolnya mengisi form dengan nilai baru tapi tidak menulis apa pun ke database, jadi begitu layar ditutup semua hilang padahal snackbar tetap bilang berhasil; sekarang hasilnya disimpan, request benar-benar ke jaringan bukan memutar cache yang bisa sudah 30 hari, dan aplikasi memberi tahu kalau permintaan dilewati karena rate limit.
- **Ketukan Riwayat jalan.** Ketuk baris di Riwayat tidak lagi gagal diam-diam: memutar lagu yang file-nya hilang melempar error yang tidak tertangani, jadi ketukannya tidak terjadi tanpa pesan apa pun.
- **Angka dashboard segar.** Bersihkan riwayat kini menyegarkan angka dashboard, karena kartu ringkasan di-cache 10 menit sementara daftar detail selalu diambil segar, jadi satu layar bisa menampilkan dua versi angka yang berbeda.

## Peningkatan

- **Notifikasi lebih ringan.** Notifikasi tidak lagi membangun ulang seluruh antrean tiap perubahan state: media session membuat satu objek per lagu antrean sebelum sempat mengecek apakah antrean berubah, dan itu boros saat menggeser volume atau mengubah kecepatan.
- **Rescan jujur.** Rescan manual jujur soal rate limit, bukan melaporkan berhasil padahal tidak ada yang diambil.
- **119 test.** 119 test mencakup regression suite baru untuk mencegah metadata terhapus, balapan antar scan, dan rescan yang tidak menyimpan supaya tidak bisa kembali lagi.

## v2.6.2

Rilis ini menghadirkan penulisan playlist lebih ringan dan import M3U lebih aman.

## Perbaikan bug

- **Import M3U akurat.** Import M3U tidak lagi menambah lagu yang salah: kalau sebuah entry hanya cocok dari nama file dan beberapa lagu punya nama sama, aplikasi mengambil yang pertama secara acak, dan nama yang ambigu kini dilaporkan sebagai tidak cocok, bukan ditebak.
- **Lagu fade-in aman.** Bersihkan antrean tetap menyisakan lagu yang sedang fade-in, karena menekan tombol itu saat crossfade berjalan bisa menghapus lagu yang sedang terdengar.
- **Durasi header akurat.** Durasi pustaka di header selalu akurat, karena sekarang dijumlahkan sekali per pemuatan dan disesuaikan saat lagu dihapus.

## Peningkatan

- **Satu transaksi.** Menambah banyak lagu ke playlist kini satu transaksi, bukan membaca ulang seluruh playlist dan posisi baris untuk tiap lagu, sehingga merge, tambah massal, atau import M3U tidak lagi berjalan kuadratik dan pemilihan besar tidak terasa lambat.
- **Update pustaka sekali.** Hapus duplikat memperbarui pustaka sekali, bukan membangun ulang peta baris dan peta A-Z untuk tiap baris yang dihapus.
- **Restore backup efisien.** Restore backup mengecek id lagu dengan satu query dan memasukkan anggota playlist dalam satu transaksi, bukan satu round trip per anggota.
- **Header lebih ringan.** Header tidak lagi menjumlahkan ulang seluruh durasi tiap rebuild, dan itu sumber utama tersendat saat scan metadata.
- **114 test.** 114 test mencakup pencocokan path M3U dan kasus nama file ambigu, supaya lagu yang salah tidak bisa kembali diam-diam.

## v2.6.1

Rilis ini berisi perbaikan audit untuk v2.6.0.

## Perbaikan bug

- **Riwayat aman.** v2.6.0 menghapus riwayat lebih dari 12 bulan secara otomatis saat upgrade database, dan karena total di dashboard dihitung dari riwayat itu tanpa filter tanggal, Total listened, Top songs, Top artists, dan grafik jam bisa menyusut tanpa jejak; sekarang pembersihan jadi aksi yang kamu jalankan sendiri di Pengaturan, dan dialognya menyebutkan terus terang bahwa angka tersebut akan turun.
- **Pragma benar-benar berlaku.** WAL dan pragma lain dijalankan dari dalam transaksi migrasi, tempat SQLite menolak pergantian journal mode dan kegagalannya ditelan; sekarang keduanya dijalankan sebelum transaksi dan hasilnya diverifikasi.
- **Startup tidak tertahan.** Prune jalan di dalam transaksi migrasi meski komentarnya bilang fire and forget, sehingga database ikut tertunda.
- **Perbandingan tanggal benar.** Perbandingan tanggal pada pembersihan riwayat kini benar, jadi entri hasil restore backup dengan offset timezone tidak lagi berisiko terhapus.
- **Index cocok dengan sort.** Index artis dan album memakai collation berbeda dari query, jadi SQLite mengabaikannya dan setiap sort tetap full scan; index juga dicoba ulang setiap buka, sehingga index yang gagal sekarang akan pulih sendiri.
- **Index A-Z selalu baru.** Lompat A-Z dan hasil search tidak lagi basi saat metadata berubah tanpa jumlah lagu berubah, misalnya setelah scan metadata.
- **Jadwal tidur andal.** Ada flag sisa yang bisa menghentikan playback setelah lagu pertama, dan sheet tidak memperbarui tampilan saat sesi terjadwal dimulai selagi sheet terbuka.
- **Kecepatan diingat.** Kecepatan dan nada diingat setelah app ditutup, dan menggeser slider tidak lagi membangun ulang seluruh layar player tiap frame.
- **Pilih semua aman.** Operasi pilih semua dibatasi jumlahnya, penulisan massal diproses bertahap, dan pesan hasil sekarang melaporkan apa yang benar-benar terjadi, bukan jumlah yang diminta.
- **Baris tidak meluber.** Baris list tidak lagi meluber saat pengaturan ukuran teks dinaikkan.
- **Search lebih stabil.** Hasil search tidak lagi dibangun ulang seluruhnya tiap play atau pause, dan kerja pengelompokan di-cache, tidak diulang tiap update progres scan.

## Peningkatan

- **Paritas lokalisasi dijaga.** Paritas lokalisasi dijaga test: setiap key English harus ada di Indonesian dengan placeholder yang sama.
- **Test regresi prune.** Test regresi mencegah pembersihan riwayat otomatis agar tidak kembali lagi.

## v2.6.0

Rilis ini menghadirkan daftar penuh, kontrol kecepatan, dan acak pintar.

## Fitur baru

- **List penuh.** Semua list sekarang menampilkan seluruh isi tanpa tombol Load more, dan scroll tetap halus di pustaka besar.
- **Lompat A-Z instan.** Lompat A-Z instan lewat peta huruf di memori, dan shuffle atau putar selalu mencakup semua lagu.
- **Lompat ke kini.** Tombol lompat ke lagu yang sedang diputar muncul saat lagu itu berada di luar layar.
- **Pilih semua.** Kamu bisa memilih semua baris langsung dari bar multi-select.
- **Kecepatan dan nada.** Kecepatan putar 0.5x sampai 2.0x plus kontrol nada, berlaku langsung dan bisa direset, tersedia dari chip di player.
- **Acak pintar.** Acak pintar memprioritaskan lagu yang jarang diputar dan lama tidak diputar.
- **Jadwal tidur harian.** Jadwal tidur harian menjalankan sleep timer 30 menit secara otomatis pada jam pilihan.
- **Tombol Putar semua.** Tombol Putar semua dan Acak kini tersedia di layar Album, Artis, dan Genre.

## Peningkatan

- **Database lebih cepat.** Database berjalan di mode SQLite WAL dengan pragma yang dioptimasi, baca memory mapped, plus index baru untuk artis, album, judul, dan waktu putar.
- **Riwayat dipangkas.** Riwayat pendengaran dibersihkan otomatis (12 bulan, dengan batas baris) agar database tetap kecil.
- **Search lebih ringan.** Search tidak lagi memakai paging: hasil dirender lazy dengan debounce 250 ms dan penjaga hasil basi.
- **Thumbnail lebih kecil.** Cover di semua list di-decode pada ukuran kecil, menghemat memori dan mengurangi lag.

## Perbaikan bug

- **Link browser kembali.** Cari lirik di Google (dan link developer) kembali bisa membuka browser, karena aplikasi tidak bisa melihat browser apa pun di Android 11 ke atas tanpa deklarasi package visibility, dan sekarang tidak lagi bergantung pada pengecekan canLaunch yang selalu gagal di sana.

## v2.5.0

Gabungkan playlist, buat equalizer custom, dan ganti ke tema AMOLED hitam pekat.

## Fitur baru

- **Gabung playlist.** Gabungkan satu playlist ke playlist lain, lewati yang duplikat.
- **Lirik hilang.** Daftar lirik yang hilang dengan fetch ulang massal.
- **Crossfade bisa diatur.** Durasi crossfade bisa diatur dari 0 sampai 12 detik.
- **Equalizer custom.** Equalizer custom 5-band.
- **Tema AMOLED.** Opsi tema hitam pekat AMOLED.
- **Shortcut dan ukuran teks.** Shortcut launcher dan pengaturan ukuran teks tersedia.

## v2.4.1

Perbaikan resume yang bisu, preset equalizer yang terdengar, dan kredit developer yang jujur.

## Perbaikan bug

- **Resume bisu.** Pause lalu resume tidak lagi bisu; resume tidak lagi celup lewat volume nol, dan play yang gagal melaporkan error lalu retry.
- **Preset terdengar.** Equalizer kini memakai skala millibel yang benar, jadi preset benar-benar terdengar.
- **Shuffle se-library.** Shuffle dan putar di Semua Lagu mencakup seluruh library, bukan cuma baris ter-render, dan lompat A-Z memuat halaman bila perlu.
- **Kredit jujur.** About menampilkan versi asli plus kredit developer yang rapi dengan logo.

## v2.4.0

Ulangi segmen lagu untuk latihan dan aksi cepat dari ikon aplikasi.

## Fitur baru

- **Ulangi A-B.** Ulangi segmen lagu mana pun untuk latihan.
- **Edit massal.** Ubah genre dan artist banyak lagu sekaligus.
- **Shortcut launcher.** Acak favorit dan lanjutkan mendengarkan langsung dari ikon app.
- **Ukuran teks.** Atur ukuran teks dari kecil sampai sangat besar.

## Peningkatan

- **Artwork lebih mulus.** Artwork tampil lebih mulus dengan image update tanpa kedip.

## v2.3.2

Equalizer yang lebih andal dan logo resmi aplikasi.

## Fitur baru

- **Logo resmi.** Ikon launcher dan logo splash Swara resmi.

## Peningkatan

- **UI lebih mulus.** Rebuild list selektif dan countdown terisolasi membuat UI lebih mulus.

## Perbaikan bug

- **Equalizer macet.** Ganti preset equalizer tidak lagi macet; call plugin kini timeout, bukan hang.
- **Resume bisu.** Pause lalu resume tidak lagi bisu karena operasi volume diserialisasi.
- **Antrean akurat.** Antrean notifikasi tetap benar dengan lagu duplikat dan reorder.

## v2.3.1

Perbaikan stabilitas mendalam di scan library, timer, lirik, dan startup.

## Perbaikan bug

- **Scan lebih aman.** Scan ulang library tidak lagi menghapus metadata hasil enrich dan edit manual.
- **Sleep timer.** Sleep timer kini jalan dengan crossfade aktif, dan repeat-one tetap konsisten.
- **Ketuk cepat.** Ketuk cepat tidak lagi memutar lagu yang berbeda dari yang tampil.
- **Retry lirik.** Gagal lirik saat offline di-retry, bukan diabaikan 90 hari.
- **Kontrol aksesibel.** Tombol repeat jadi button aksesibel, dan mini player serta chip sort punya ripple.
- **Startup lebih cepat.** Startup tidak lagi tertahan dialog izin notifikasi.

## v2.2.0

Equalizer yang benar-benar berfungsi dan perkakas library yang baru.

## Fitur baru

- **Equalizer beneran.** Equalizer yang berfungsi dengan 9 preset membentuk suara putar, tidak lagi sekadar visual.
- **Pencari duplikat.** Temukan lagu duplikat dan bersihkan sekaligus.
- **Cover hilang.** Daftar cover yang hilang dengan fetch ulang massal.
- **Folder playlist.** Susun playlist ke dalam folder.
- **Pencarian toleran.** Pencarian memaafkan kesalahan kecil, "faded alan walker" ketemu untuk "faded - alan walker".

## v2.1.0

Bagikan kartu rekap tahunan sebagai gambar dan nikmati antrean yang lebih pintar.

## Fitur baru

- **Rekap bisa dibagikan.** Bagikan kartu rekap tahunan sebagai gambar.
- **Antrean jadi playlist.** Simpan antrean putar sebagai playlist sekali ketuk.
- **Jadwal tidur.** Sleep timer pada jam tetap setiap malam.
- **Multi-select diperluas.** Multi-select diperluas ke hasil pencarian dan favorit.
- **Sortir album.** Album bisa diurutkan.
- **Kontrol antrean asli.** Notifikasi dan lockscreen kini memakai antrean asli dengan next/previous yang benar.

## v2.0.0

Semua sejak v1.6 dalam satu tonggak: aplikasi bilingual dengan Inggris sebagai bahasa utama, smart playlist, lirik sinkron, backup dan restore, rekap tahunan, plus build yang jauh lebih ringan dan cepat.

## Fitur baru

- **UI English-first.** Antarmuka Inggris kini jadi default, dengan Bahasa Indonesia di Pengaturan (390+ string terlokalisasi).
- **Smart auto-playlists.** Daily Mix dan Unplayed dibuat secara otomatis.
- **Lirik sinkron.** Lirik LRC tersinkron dengan highlight mengikuti lagu.
- **Sleep timer.** Sleep timer dengan fade-out yang lembut.
- **Backup dan restore.** Backup dan restore data lewat JSON.
- **Onboarding.** Alur onboarding saat pertama dibuka.
- **Rekap tahunan.** Rekap tahunan, streak, dan genre teratas bulan ini.
- **Import dan berbagi.** Import M3U, berbagi lagu, dan kolase cover playlist.

## Peningkatan

- **Di balik layar.** APK per arsitektur, list paging SQL, player lazy, fetch metadata ditunda dengan cache, lirik gzip, dan nol masalah `flutter analyze` dengan 75 test lolos.

## v1.9.1

Rilis ini menghadirkan import M3U, berbagi lagu, dan streak.

## Fitur baru

- **Import M3U.** Import playlist dari file .m3u/.m3u8, dicocokkan ke library.
- **Berbagi lagu.** Bagikan lagu (info plus file audio) dari menu lagu.
- **Streak harian.** Dashboard menampilkan streak harian dan genre teratas bulan ini, dengan agregat ter-cache.
- **Cold start lebih cepat.** Inisialisasi paralel di balik splash screen membuat cold start lebih cepat.

## Peningkatan

- **Cover remote di-cache.** Cover art remote di-cache di disk (LRU 100MB), bukan diunduh ulang tiap buka app.
- **Playlist on-demand.** Data playlist dimuat saat dibutuhkan, dan font ikon yang tak terpakai dibuang.

## v1.9.0

Rilis ini menghadirkan playlist pintar dan lirik sinkron.

## Fitur baru

- **Smart playlist otomatis.** Smart playlist otomatis Daily Mix (25 lagu segar tiap hari, bisa diacak ulang) dan Unplayed dirawat otomatis.
- **Lirik sinkron.** Lirik sinkron (LRC) dengan highlight mengikuti lagu dan auto-scroll, plus toggle tampilan biasa.
- **Sleep timer memudar.** Sleep timer memudarkan volume, bukan berhenti mendadak.
- **Backup dan restore.** Export dan import playlist, favorit, dan riwayat sebagai JSON, plus info ukuran dan bersih-bersih cache cover album.
- **Onboarding pertama.** Rilis ini menghadirkan onboarding saat pertama dibuka.
- **Toggle notifikasi jelas.** Tombol shuffle/repeat notifikasi kini jelas aktif atau tidak.
- **UI dipoles.** Padding konsisten, loading skeleton, empty state rata tengah, dan touch target 48px memoles UI.

## Peningkatan

- **Cache lirik lebih lama.** Hasil fetch lirik di-cache lebih lama, dan lirik sinkron tersimpan lokal.

## v1.8.3

Rilis ini membuat pemakaian data lebih hemat dan memori lebih ringan.

## Fitur baru

- **Playlist on-demand.** Data playlist kini dimuat saat dibutuhkan, bukan saat startup.

## Peningkatan

- **Negative cache lirik.** Lirik yang tidak ketemu diingat (negative cache 90 hari), bukan di-fetch ulang tiap buka lagu.
- **Satu HTTP client.** Satu HTTP client bersama untuk semua traffic metadata (koneksi tidak diulang-ulang).
- **Cover ukuran tampil.** Cover album di-decode sesuai ukuran tampil (thumbnail untuk tile, penuh hanya di player).

## v1.8.2

Rilis ini membuat instalasi lebih ramping dan baterai lebih hemat.

## Fitur baru

- **Hanya arsitektur HP.** Kini hanya arsitektur HP yang dipublish (arm64 + armv7), tidak ada lagi build khusus emulator di download.
- **Widget test pertama.** Widget test pertama hadir di antara total 67 test.

## Peningkatan

- **Metadata di-cache.** Respons metadata di-cache di disk (30 hari, miss 90 hari) sehingga install ulang tidak fetch ulang semuanya.
- **Lirik terkompresi.** Lirik disimpan terkompresi gzip di database.
- **Position stream tidur.** Position stream tidur saat pause, dan sync notifikasi lebih sedikit kerja redundan.
- **Widget image bawaan.** Dependency image-caching yang berat dibuang, diganti widget image bawaan.

## v1.8.1

Rilis ini menghadirkan download lebih ringan dan startup lebih cepat.

## Fitur baru

- **APK per arsitektur.** Download build kecil sesuai HP, bukan satu APK universal.
- **List panjang berhalaman.** List panjang (Semua Lagu, Search) dirender per halaman 200 dengan tombol Muat lagi.
- **Unit test pertama.** Unit test pertama hadir: 46 test untuk parsing nama file dan helper formatting.

## Peningkatan

- **Download lebih kecil.** Download jauh lebih kecil via split-per-ABI, obfuscation, resource dipangkas, dan R8 keep rules dipersempit.
- **Tampil lebih cepat.** Daftar lagu muncul tepat setelah frame pertama; fetch metadata berat ditunda dan backoff saat rate limit.
- **Player kedua lazy.** Player audio kedua kini dibuat lazy hanya saat crossfade aktif.
- **Sync lebih ringan.** Sync notifikasi melewati kerja redundan tiap detik, dan animasi indikator berhenti saat pause.

## Perbaikan bug

- **Build CI jujur.** Step build CI tidak lagi menelan failure asli.

## v1.8.0

Rilis ini menjadikan English bahasa default aplikasi, dengan Bahasa Indonesia sejauh satu ketukan di Pengaturan.

## Fitur baru

- **Default English.** UI aplikasi kini default English; ganti ke Bahasa Indonesia kapan saja di Pengaturan, diingat antar sesi.
- **Section Bahasa.** Section Bahasa baru di Pengaturan menawarkan opsi English dan Bahasa Indonesia.

## Peningkatan

- **Lokalisasi ARB.** Seluruh ~390 string user-facing pindah ke file lokalisasi ARB (satu sumber utama, tidak lagi tercecer di tiap layar).
- **Komentar kode English.** Komentar kode diterjemahkan ke English di seluruh codebase.

## Perbaikan bug

- **Pesan terlokalisasi.** Pesan validasi, error, dan konfirmasi kini ikut bahasa yang dipilih, termasuk error level provider.
- **intl di-bump.** intl di-bump mengikuti kebutuhan flutter_localizations.

## v1.7.0

Rilis ini bersih-bersih besar di balik layar: kebocoran player diperbaiki, query database dioptimalkan, dan aksi massal jadi instan.

## Fitur baru

- **Favorit massal.** Pilih banyak lagu dan favoritkan semuanya dalam satu aksi.
- **Status error dashboard.** Dashboard menampilkan status error dengan tombol coba lagi, tidak loading selamanya saat database gagal.
- **Label sleep-timer live.** Label sleep-timer mode jumlah lagu ter-update secara live.

## Peningkatan

- **Query tersering satu JOIN.** Query lagu tersering kini satu JOIN, tidak lagi memuat seluruh library ke memori, dengan index database baru untuk sorting dan query dashboard.
- **Folder satu query.** Layar folder cukup satu query lalu grouping di memori (sebelumnya satu full scan per folder).
- **Pencarian di-debounce.** Input pencarian di-debounce dan hasil dihitung sekali per build.
- **Dashboard paralel.** Dashboard memuat semua statistik secara paralel.
- **Edit lirik dihormati.** Auto-fetch lirik tidak lagi menimpa edit manual judul/artis/album.
- **Migrasi Flutter 3.47.** Kode dimigrasikan ke API Flutter 3.47 (RadioGroup, onReorderItem, withValues).
- **Analisis bersih.** Aplikasi terverifikasi dengan nol masalah `flutter analyze`.

## Perbaikan bug

- **Kebocoran player diperbaiki.** Kebocoran audio player dan stream-subscription diperbaiki (dispose benar, ikon play/pause tidak macet setelah crossfade).
- **Race antrean diperbaiki.** Race antrean saat menambah lagu ke antrean kosong diperbaiki.
- **Player crossfade diperbaiki.** Repeat/shuffle/speed kini tidak bekerja ke player internal yang salah saat crossfade.
- **Crash diperbaiki.** Crash dari judul/artis kosong, baris database korup, dan file art hilang di notifikasi diperbaiki.
- **Teks EQ diperbaiki.** Teks EQ yang menyesatkan diperbaiki (itu preset visual, tidak mengubah suara asli).
- **Service mati dihapus.** Notification service mati yang mereferensikan dependency yang sudah dibuang dihapus.

## v1.6.0

Rilis ini menghadirkan tab perpustakaan yang bisa dikonfigurasi dan koleksi yang didesain ulang.

## Fitur baru

- **Tab perpustakaan konfigurabel.** Halaman "Musik" berganti nama menjadi **Perpustakaan**, dengan tab yang bisa dikonfigurasi: **Lagu, Album, Artis, Folder, Genre** (aktif/nonaktif dan drag-and-drop lewat sheet pengaturan).
- **Tab Album baru.** Tab **Album** baru menampilkan grid cover art 2 kolom.
- **Koleksi didesain ulang.** Koleksi kini menampilkan 4 kartu akses cepat berwarna (**Favorit, Baru Ditambahkan, Baru Diputar, Paling Sering Diputar**) di atas daftar playlist.
- **Halaman Search baru.** Halaman **Search** baru (ikon kaca pembesar di AppBar) dengan filter: **Lagu, Album, Artis, Folder, Genre**.
- **Header collapsible.** Header collapsible hadir di semua halaman: tombol Mulai Putar + Acak naik saat di-scroll.
- **Popup A-Z.** Popup huruf A-Z pada scrollbar mengikuti posisi jari, dengan animasi fade-out.
- **Timer tidur dibangun ulang.** Timer tidur dibangun ulang dengan drum picker ala iOS (jam/menit atau jumlah lagu), countdown besar, dan tombol berhenti serta tutup.
- **Multi-select lagu.** Multi-select lagu via long-press: favoritkan atau tambahkan ke playlist sekaligus.
- **10 warna aksen.** 10 warna aksen kustom tersedia dan tersimpan antar sesi.
- **Preset EQ.** Preset EQ (Flat, Pop, Rock, Classical, Jazz, Electronic, Hip-Hop, Bass Boost, Vocal) hadir dengan visualizer animasi.
- **Dashboard dirombak.** Dashboard tidak lagi menduplikasi Koleksi: grafik aktivitas 7 hari, Top 5 lagu + artis, distribusi genre, lagu yang belum diputar.

## Peningkatan

- **Scan satu kali.** Musik langsung muncul dari database lokal; scan device hanya berjalan bila perlu atau setelah 30 menit.

## v1.4.0

Pemutaran di background kini memakai foreground service asli Android dengan MediaSession, jadi kontrol di notifikasi dan lockscreen akhirnya bekerja dengan benar.

## Fitur baru

- **Foreground service.** Kontrol musik kini memakai foreground service Android asli dengan MediaSession: kontrol di notifikasi dan lockscreen (play/pause/next/previous) akhirnya bekerja dengan benar, menggantikan notifikasi ikon biasa lama yang bisa membuat musik berhenti sendiri di background.
- **Label sleep timer hidup.** Hitung mundur sleep timer kini tampil langsung di halaman player (menit:detik atau jumlah lagu tersisa).

## Perbaikan bug

- **Indikator sedang diputar.** Indikator "sedang diputar" di Semua Lagu terupdate seketika saat lagu berganti; sebelumnya baru setelah keluar dan kembali ke halaman.
- **Indikator di mana-mana.** Folder, Playlist, dan Favorit kini menampilkan indikator "sedang diputar"; sebelumnya tidak.
- **Tanpa toast konfirmasi.** Notifikasi konfirmasi sleep timer yang menutupi tombol kontrol player dihapus.
- **Player lebih bersih.** Teks "Ketuk cover untuk lihat lirik" dihapus agar player lebih bersih.

## v1.3.0

Rilis ini adalah perombakan stabilitas mendalam: pemindaian yang aman dan tidak pernah menghapus pustaka secara tak terduga, sleep timer kustom yang berfungsi, dan repeat yang sadar crossfade.

## Peningkatan

- **Sortir di mana-mana.** Sortir A-Z, Z-A, Artis, dan Baru Ditambahkan kini tersedia di Folder, Favorit, dan Playlist.
- **A-Z di koleksi.** Navigasi A-Z di scrollbar kini tersedia di Folder dan Favorit.
- **Ingat sortir.** Pilihan sortir diingat per halaman.
- **Scan hanya manual.** Scan metadata tidak lagi berjalan otomatis saat buka aplikasi, hanya saat diminta.
- **Gerak lebih halus.** Transisi dan animasi item lebih halus di semua halaman.
- **Pelindung data scan.** Scan tidak pernah menghapus pustaka bila MediaStore tiba-tiba kosong (misalnya setelah reboot atau izin baru).
- **Judul stabil.** Judul lagu panjang tidak lagi berkedip saat ada notifikasi masuk.

## Perbaikan bug

- **Sleep timer kustom.** Sleep timer kustom (jam dan menit) kini benar-benar bisa diatur.
- **Sleep timer menghentikan.** Sleep timer benar-benar menghentikan musik; sebelumnya itu me-pause player yang salah.
- **Repeat dengan crossfade.** Repeat-one kini bekerja saat crossfade aktif.
- **Cocokkan awalan folder.** `/storage/Music` tidak lagi menampilkan lagu dari `/storage/Music2` dan folder bernama mirip.
- **Refresh folder.** Metadata folder ter-update langsung setelah scan, tanpa perlu keluar dari folder.
- **Reorder playlist.** Drag reorder playlist tidak lagi berkedip.
- **Hasil pencarian kosong.** Tombol Putar dan Acak nonaktif saat hasil pencarian kosong, mencegah crash RangeError.
- **Acak benar-benar acak.** Shuffle selalu mulai dari lagu yang benar-benar acak.
- **Notifikasi background.** Notifikasi kontrol musik lebih responsif di background.
- **Favorit saat simpan.** Status favorit tidak lagi ter-reset saat menyimpan edit metadata.
- **Kebocoran memori.** Perbaiki memory leak di halaman edit metadata dan error tersembunyi saat navigasi ke halaman yang sudah ditutup.

## v1.2.1

Tombol favorit akhirnya benar-benar toggle dan crossfade berjalan terus antar lagu, bukan hanya di transisi pertama.

## Perbaikan bug

- **Toggle favorit.** Tombol Favorit di menu titik tiga kini benar-benar toggle; sebelumnya selalu menambah, jadi lagu tidak pernah bisa di-unfavorite dari sana.
- **Crossfade berkelanjutan.** Crossfade kini berjalan terus antar lagu; sebelumnya hanya transisi pertama yang bekerja.
- **Crash dashboard.** Perbaiki crash dashboard saat menampilkan grafik 7 hari.
- **Acak selalu aktif.** Shuffle selalu mengaktifkan; sebelumnya bisa mematikan shuffle bila sudah aktif.
- **Baru ditambahkan.** Sort "Baru ditambahkan" kini memakai waktu tambah pustaka yang sebenarnya.
- **Cover ter-cache.** Album art kini di-cache lokal, tidak diambil ulang setiap saat.
- **Scan metadata per batch.** Scan metadata massal berjalan per batch: lebih cepat dan ramah ke API gratis.
- **Path tidak wajar.** Perbaiki potensi crash saat memindai file dengan path tidak wajar.

## v1.2.0

Navigasi cepat A sampai Z dan antrean putar yang bisa diatur membuat pustaka besar lebih cepat dijelajahi.

## Fitur baru

- **Lompat A-Z.** Navigasi cepat A sampai Z penuh, melompat ke huruf terdekat yang tersedia.
- **Antrean putar.** Antrean yang bisa diatur: seret untuk mengubah urutan, swipe kiri untuk menghapus.
- **Menu per lagu di semua tempat.** Menu per lagu yang lengkap (putar berikutnya, playlist, rename, edit, hapus) kini juga ada di Folder dan Favorit.
- **Tombol putar dan acak.** Tombol Mulai Putar dan Acak di Folder, Playlist, dan Favorit, tidak hanya di Semua Lagu.
- **Tampilan lirik.** Ketuk lirik untuk kembali ke tampilan cover; tombol edit lirik selalu terlihat.
- **Judul berjalan.** Judul lagu panjang otomatis bergulir rapi di halaman player.
- **Folder benar-benar tersembunyi.** Folder tersembunyi kini benar-benar tidak muncul di Semua Lagu.

## Perbaikan bug

- **Mini player.** Mini player kini langsung muncul begitu musik mulai, dari halaman mana pun.
- **Kontrol notifikasi.** Notifikasi kontrol musik kini punya izin dan tombol ikon yang benar.

Catatan: notifikasi kontrol musik masih dalam penyempurnaan dan bisa tidak stabil di beberapa perangkat.

## v1.1.0

Gestur, sleep timer, dan tema: rilis ini mengubah pemutar jadi pengalaman layar penuh yang bisa dioper dengan gestur yang mudah diingat.

## Fitur baru

- **Gestur swipe.** Swipe ke bawah di player untuk minimize; swipe kiri/kanan untuk lagu berikut/sebelumnya.
- **Lirik sekali ketuk.** Ketuk cover album untuk melihat lirik seketika; cari lirik lewat Google bila auto-fetch tidak menemukan.
- **Sleep timer dan kecepatan.** Sleep timer dengan durasi kustom; kontrol kecepatan 0.5x sampai 2x.
- **Cari dan sortir.** Pencarian lagu real-time; sortir A-Z/Z-A/genre/tanggal.
- **Folder dan rescan.** Sembunyikan folder dari library; scan ulang metadata per lagu atau sekaligus.
- **Pengaturan dan tema.** Halaman pengaturan dengan tema terang/gelap; animasi mulus di mana-mana.

## Perbaikan bug

- **Putar pertama.** Player kini langsung muncul saat pertama kali diputar; sebelumnya perlu putar dua kali.

## v1.0.0

Rilis pertama pemutar musik offline untuk Android, dibangun dengan Flutter: pindai koleksi dan aplikasi melengkapi judul, artis, album art, genre, dan lirik lewat internet, sementara semua data dengar tetap tersimpan lokal dan bisa diakses offline.

## Fitur baru

- **Pemutaran offline.** Pindai dan putar musik langsung dari penyimpanan HP.
- **Metadata otomatis.** Judul, artis, album art, genre, dan lirik diambil lewat internet saat diminta.
- **Dashboard.** Jam dengar 7 hari terakhir, lagu dan artis tersering, distribusi genre dan region.
- **Dasar pustaka.** Jelajah per folder; playlist kustom, favorit, dan baru diputar.
- **Kontrol pemutaran.** Shuffle, repeat (mati/semua/satu), dan sleep timer; edit metadata manual.
