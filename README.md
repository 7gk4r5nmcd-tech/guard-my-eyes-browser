# Guard My Eyes Browser

Browser untuk iPhone & Android dengan AI yang berjalan di HP sendiri:

- Mengunci halaman yang berisi konten porno/hentai, konten seksi, atau wajah wanita.
- Mengunci video game di YouTube (kategori "Gaming" atau kata kunci judul).
- Mengunci situs porno berdasarkan nama situs, judul, label, dan menu situs.
- Untuk keluar dari layar peringatan, kamu harus mengetik ulang komitmen dan doa Salam Maria.

Kode di sini dibuat dari ekstensi laptop **Guard My Eyes**. File `.ipa` dan `.apk` dibuat otomatis oleh
GitHub Actions setiap kali kode berubah, lalu diterbitkan di halaman **Releases** repo ini.

---

## Pasang di iPhone (gratis, pakai Apple ID biasa)

### Yang dibutuhkan
- Laptop Windows + kabel iPhone.
- **Sideloadly**: https://sideloadly.io
- **iTunes** dan **iCloud** versi *web* dari Apple (bukan dari Microsoft Store). Tautannya ada di halaman
  unduhan Sideloadly; kalau versi Microsoft Store sudah terpasang, hapus dulu.

### Langkah
1. Di laptop, unduh **GuardMyEyes.ipa** dari halaman **Releases** repo ini.
2. Colokkan iPhone ke laptop. Di iPhone ketuk **Trust / Percayai**.
3. Buka **Sideloadly**, seret file `GuardMyEyes.ipa` ke jendelanya.
4. Isi **Apple ID** kamu, klik **Start**, masukkan kata sandi dan kode verifikasi 2 langkah bila diminta.
   *Saran: pakai Apple ID cadangan bila ragu memasukkan Apple ID utama ke aplikasi pihak ketiga.*
5. Di iPhone, nyalakan **Developer Mode**: Settings → Privacy & Security → Developer Mode → On → restart.
6. Percayai aplikasinya: Settings → General → VPN & Device Management → pilih Apple ID kamu → **Trust**.
7. Buka **Guard My Eyes** dari layar utama.

### Setiap 7 hari
Aplikasi dari Apple ID gratis kedaluwarsa setelah 7 hari. Colokkan iPhone dan ulangi langkah 3–4
(atau nyalakan **Automatic Refresh** di Sideloadly supaya diperpanjang otomatis selama laptop menyala).

### Supaya tidak ada celah
Settings → Screen Time → Content & Privacy Restrictions (pakai passcode yang dipegang orang lain):
- **Allowed Apps** → matikan **Safari**.
- **iTunes & App Store Purchases → Installing Apps → Don't Allow**, lalu hapus Chrome & browser lain.

---

## Pasang di Android

1. Di HP, buka halaman **Releases** repo ini dan unduh **app-release.apk**.
2. Buka file-nya, izinkan **Install unknown apps** untuk browser/Files bila diminta, lalu **Install**.
3. Jadikan browser bawaan: Settings → Apps → Default apps → Browser → **Guard My Eyes**.
4. Matikan Chrome: Settings → Apps → Chrome → **Disable**.

---

## Keterbatasan versi HP
- Video dari server lain yang tidak bisa dibaca tetap di-blur (belum dianalisis seperti di laptop).
- AI memakai model ringan (MobileNet) supaya hemat baterai.
