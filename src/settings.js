// Pengaturan bawaan. Semua bisa diubah lewat halaman Options.
export const DEFAULT_SETTINGS = {
  detectPorn: true,          // blokir konten porno/hentai
  detectSexy: true,          // blokir juga gambar "seksi" (pakaian minim, pose sugestif)
  detectFemaleFace: true,    // blokir bila ada wajah wanita
  aiMode: "accurate",        // "accurate" (InceptionV3) atau "light" (MobileNetV2, untuk komputer lemah)
  pageSuspiciousCount: 3,    // kunci halaman bila sebanyak ini gambar "agak mencurigakan"
  pornThreshold: 0.6,        // ambang skor Porn (atau Porn + Hentai)
  hentaiThreshold: 0.35,     // ambang skor Hentai sendiri (gambar kartun/anime porno sering bercampur skor "Drawing")
  sexyThreshold: 0.75,       // ambang skor Sexy
  femaleThreshold: 0.75,     // keyakinan model bahwa wajah itu wanita
  minFaceSize: 40,           // wajah lebih kecil dari ini (px, pada gambar yang dianalisis) diabaikan
  minImageSize: 80,          // gambar lebih kecil dari ini (px) tidak diperiksa
  blurUntilChecked: true,    // blur semua gambar/video sampai lolos pemeriksaan
  holdPage: true,            // sembunyikan halaman sampai gambar pertama selesai diperiksa
  holdMaxMs: 4000,           // batas maksimal penundaan halaman (ms)
  checkVideos: true,         // ambil cuplikan video secara berkala
  blockPornSites: true,      // kunci langsung situs porno (berdasarkan nama domain)
  pornSites:
    "bokepindo.id\npornhub.com\nxvideos.com\nxnxx.com\nxhamster.com\nspankbang.com\neporner.com\nredtube.com\nyouporn.com\nnhentai.net\nhanime.tv\nhentaihaven.xxx\nrule34.xxx\nonlyfans.com\nupload18.cc",
  pornDomainKeywords: "sex\nbokep\nporn\nhentai\nxxx\nxnxx\nxvideo\nxhamster\nnsfw\nrule34\nonlyfans\nbrazzers\nhanime",
  blockByTitle: true,        // kunci halaman yang judul/alamatnya berisi kata kunci porno
  pornTitleKeywords:
    "milf\nbokep\nporn\nporno\nhentai\nxxx\njav\nngentot\ncolmek\nbugil\ntelanjang\nmesum\nfilm semi\nsemi korea\nsemi jepang\nsemi barat\nerotic\nerotis\nnsfw\nonlyfans\n18+\nstepmom\nstepsister\nvivamax\nsex\nsex video\nvideo sex",
  pornTagKeywords: "sexy\n17+\n21+", // tambahan khusus untuk label/tag/genre halaman
  scanPageMenu: true,        // kunci situs yang menunya punya >= 2 kategori porno
  blurUnreadableVideos: true, // video yang tidak bisa diperiksa (dari server lain) tetap di-blur
  detectGaming: true,        // kunci video game di YouTube & situs streaming game
  gamingKeywords:
    "gameplay\nwalkthrough\nlet's play\nspeedrun\nmabar\npush rank\nminecraft\nroblox\nmobile legends\nmlbb\nfree fire\nfreefire\npubg\nvalorant\ngenshin\nfortnite\ngta\ncall of duty\nmagic chess\nhonor of kings\nclash of clans\nclash royale\nstumble guys\nefootball\nfc mobile\ndota 2",
  gamingSites: "twitch.tv\nkick.com",
  afterFinish: "newtab",     // "newtab" | "close"
  whitelist: "",             // satu domain per baris, mis. "docs.google.com"
  commitmentText:
    "Saya mau hidup lebih baik. Ingat, konten seperti ini merusakmu dan menggodamu. Jangan biarkan iblis menang.",
  prayerText:
    "Salam Maria, penuh rahmat, Tuhan sertamu. Terpujilah engkau di antara wanita, dan terpujilah buah tubuhmu, Yesus. Santa Maria, Bunda Allah, doakanlah kami yang berdosa ini, sekarang dan waktu kami mati. Amin.",
};

export async function getSettings() {
  const stored = await chrome.storage.sync.get(DEFAULT_SETTINGS);
  return { ...DEFAULT_SETTINGS, ...stored };
}

export function isWhitelisted(hostname, whitelist) {
  const host = hostname.toLowerCase();
  return whitelist
    .split(/\s+/)
    .map((d) => d.trim().toLowerCase().replace(/^\*\./, ""))
    .filter(Boolean)
    .some((d) => host === d || host.endsWith("." + d));
}

// Cocokkan judul dengan daftar kata kunci (per baris), sebagai kata utuh.
export function matchKeyword(text, keywords) {
  const t = " " + String(text || "").toLowerCase() + " ";
  for (const raw of String(keywords || "").split("\n")) {
    const k = raw.trim().toLowerCase();
    if (!k) continue;
    const esc = k.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (new RegExp("(^|[^\\p{L}\\p{N}])" + esc + "($|[^\\p{L}\\p{N}])", "u").test(t)) return k;
  }
  return null;
}

// Apakah sebuah host termasuk situs porno: ada di daftar, atau namanya mengandung kata kunci.
export function isPornHost(host, s) {
  if (!host || !s.blockPornSites) return false;
  host = host.toLowerCase();
  if (isWhitelisted(host, s.pornSites)) return true;
  // Nama tempat/kata biasa yang kebetulan mengandung "sex" (essex.ac.uk, sussex, dll.) tidak dihitung.
  const cleaned = host.replace(/(es|sus|middle|wes)sex|sextant|sexton|sextet|sexagesim/g, "");
  return String(s.pornDomainKeywords || "")
    .split("\n")
    .map((k) => k.trim().toLowerCase())
    .filter(Boolean)
    .some((k) => cleaned.includes(k));
}
