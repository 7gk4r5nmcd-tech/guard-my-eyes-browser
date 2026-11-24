// Content script: memindai gambar & video di halaman, lalu mengunci halaman bila ada yang terlarang.
import { DEFAULT_SETTINGS, isWhitelisted, matchKeyword, isPornHost } from "./settings.js";
import { createLockScreen } from "./overlay.js";

const IS_TOP = window === window.top;

// Cegah berjalan dua kali di tab yang sama (mis. setelah ekstensi di-reload dan disuntik ulang).
// Salinan lama yang sudah "yatim" (ekstensinya sudah di-reload) tidak dihitung.
const ALREADY = typeof window.__gwAlive === "function" && window.__gwAlive();
window.__gwAlive = () => {
  try {
    return !!chrome.runtime?.id;
  } catch {
    return false;
  }
};
const OK = "data-gw-ok";
const html = document.documentElement;

let settings = DEFAULT_SETTINGS;
let locked = false;
let lockScreen = null;

// Pasang pendengar keyboard sedini mungkin supaya bisa mendahului skrip halaman saat terkunci.
for (const type of ["keydown", "keypress", "keyup"]) {
  window.addEventListener(
    type,
    (e) => {
      if (!locked || !lockScreen) return;
      if (window.__gwMobile) return void e.stopImmediatePropagation(); // HP: biarkan masuk ke textarea
      if (type === "keydown") lockScreen.onKey(e);
      else {
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    },
    true
  );
}
for (const type of ["paste", "copy", "cut", "contextmenu"]) {
  window.addEventListener(type, (e) => locked && (e.preventDefault(), e.stopImmediatePropagation()), true);
}

// Kelas di <html> yang harus kita jaga. Beberapa situs (React/Next.js dll.) menimpa atribut class
// milik <html>; tanpa penjaga ini, kelas kita bisa hilang dan konten sempat terlihat.
const wanted = new Set();
function setClass(name, on) {
  on ? wanted.add(name) : wanted.delete(name);
  html.classList.toggle(name, on);
}
new MutationObserver(() => {
  for (const c of wanted) if (!html.classList.contains(c)) html.classList.add(c);
}).observe(html, { attributes: true, attributeFilter: ["class"] });

// Tunda halaman sejak awal (hanya frame utama); dilepas setelah pemeriksaan pertama selesai.
const startedAt = performance.now();
if (IS_TOP && !ALREADY) setClass("gw-hold", true);

if (!ALREADY) init();

async function init() {
  try {
    settings = { ...DEFAULT_SETTINGS, ...(await chrome.storage.sync.get(DEFAULT_SETTINGS)) };
  } catch {}

  if (isWhitelisted(location.hostname, settings.whitelist) || location.protocol === "chrome-extension:") {
    setClass("gw-noblur", true);
    setClass("gw-hold", false);
    return;
  }
  if (!settings.blurUntilChecked) setClass("gw-noblur", true);
  if (!settings.holdPage) setClass("gw-hold", false);

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.type === "lock" && IS_TOP) lock(msg.reason);
  });

  if (IS_TOP) {
    const { flagged } = await send({ type: "isFlagged", url: location.href });
    if (flagged) {
      lock("halaman yang sebelumnya sudah terdeteksi");
      return;
    }
  }

  // Situs porno dikenali dari namanya -> langsung dikunci, tanpa menunggu AI.
  if (isPornHost(location.hostname, settings)) {
    if (IS_TOP) lock("situs porno");
    else send({ type: "flag", reason: "konten dari situs porno" });
    return;
  }

  if (IS_TOP && settings.blockByTitle) watchTitle();

  if (IS_TOP && settings.detectGaming) {
    if (isWhitelisted(location.hostname, settings.gamingSites)) {
      lock("situs streaming game");
      return;
    }
    if (/(^|\.)youtube\.com$/.test(location.hostname)) watchYouTube();
  }

  startScanning();
}

// ---------- Judul & alamat halaman ----------

// Baca label/genre/tag halaman dan menu situs.
function checkPageSignals() {
  if (locked) return;
  const s = settings;
  const tagKw = s.pornTitleKeywords + "\n" + s.pornTagKeywords;
  // 1) Label halaman: meta keywords/tag/section, dan link tag/genre/kategori milik halaman ini.
  const metas = [...document.querySelectorAll(
    'meta[name="keywords"], meta[property="article:tag"], meta[property="article:section"], meta[property="video:tag"]'
  )].map((m) => m.content || "");
  const ownTags = [...document.querySelectorAll('a[rel~="tag"], a[rel~="category"]')]
    .filter((a) => !a.closest("nav, header, footer, aside, [class*=menu], [id*=menu]"))
    .map((a) => a.textContent);
  for (const t of [...metas.join(",").split(","), ...ownTags]) {
    const kw = matchKeyword(t, tagKw);
    if (kw) return send({ type: "flag", reason: `halaman berlabel "${kw}"` });
  }
  // 2) Menu situs: kalau ada >= 2 kategori porno berbeda, berarti situs porno.
  if (!s.scanPageMenu) return;
  const found = new Set();
  for (const a of document.querySelectorAll("a[href]")) {
    let path = a.getAttribute("href") || "";
    try {
      path = decodeURIComponent(new URL(path, location.href).pathname);
    } catch {}
    const kw = matchKeyword(a.textContent + " " + path.replace(/[-_/+.=&?]+/g, " "), s.pornTitleKeywords);
    if (kw) found.add(kw);
    if (found.size >= 2) return send({ type: "flag", reason: `situs ini menyediakan konten porno (${[...found].join(", ")})` });
  }
}

function watchTitle() {
  let last = "";
  document.addEventListener("DOMContentLoaded", checkPageSignals);
  setTimeout(checkPageSignals, 3000);
  setInterval(checkPageSignals, 8000);
  const check = () => {
    if (locked) return;
    let path = location.pathname + " " + location.search;
    try {
      path = decodeURIComponent(path);
    } catch {}
    const text = (document.title + " " + path.replace(/[-_/+.=&?]+/g, " ")).trim();
    if (text === last) return;
    last = text;
    const kw = matchKeyword(text, settings.pornTitleKeywords);
    if (kw) send({ type: "flag", reason: `judul/alamat halaman berisi "${kw}"` });
  };
  check();
  document.addEventListener("DOMContentLoaded", check);
  setInterval(check, 1000);
}

// ---------- YouTube: deteksi video game ----------

function youTubeId() {
  const u = new URL(location.href);
  if (u.pathname === "/watch") return u.searchParams.get("v");
  const m = u.pathname.match(/^\/(shorts|live)\/([\w-]{11})/);
  return m ? m[2] : null;
}

function watchYouTube() {
  let lastUrl = null;
  const check = async () => {
    if (locked || location.href === lastUrl) return;
    lastUrl = location.href;
    const id = youTubeId();
    if (!id) return setClass("gw-ythold", false);

    // Selama dicek, video di-blur dan dibisukan.
    setClass("gw-ythold", true);
    let bad = false;
    try {
      const { flagged } = await send({ type: "isFlagged", url: location.href });
      if (flagged) return (bad = true), lock("video yang sebelumnya sudah terdeteksi");
      const info = await send({ type: "ytInfo", id });
      if (youTubeId() !== id) return; // sudah pindah video
      if (info && !info.error) {
        const kw = matchKeyword(info.title, settings.gamingKeywords);
        if (info.category === "Gaming") return (bad = true), send({ type: "flag", reason: "video game" });
        if (kw) return (bad = true), send({ type: "flag", reason: `video game ("${kw}")` });
      }
    } finally {
      if (!bad && !locked && youTubeId() === id) setClass("gw-ythold", false);
    }
  };
  document.addEventListener("yt-navigate-finish", check);
  setInterval(check, 700);
  check();
}

function send(msg) {
  return chrome.runtime.sendMessage(msg).catch((e) => ({ error: String(e) }));
}

// ---------- Pemindaian ----------

const BG_SELECTOR = '[style*="background"]';
const inView = new Set();
const io = new IntersectionObserver(
  (entries) => {
    for (const en of entries) {
      if (en.isIntersecting) {
        inView.add(en.target);
        checkElement(en.target);
      } else inView.delete(en.target);
    }
  },
  { rootMargin: "800px 0px" }
);

function checkElement(el) {
  if (el.tagName === "IMG") checkImage(el);
  else if (el.tagName === "VIDEO") checkVideo(el);
  else if (el.tagName.toLowerCase() === "image") checkSvgImage(el);
  else if (el.tagName === "CANVAS") checkCanvas(el);
  else checkBackground(el);
}

function track(el) {
  const tag = el.tagName;
  if (tag === "IFRAME") return void fromPornHost(el.src);
  if (tag === "IMG" || tag === "VIDEO" || tag === "CANVAS" || tag.toLowerCase() === "image") io.observe(el);
  else if (el.matches?.(BG_SELECTOR)) {
    if (bgUrl(el)) io.observe(el);
    else markOk(el);
  }
}

// Semua "akar" yang kita pantau: dokumen utama + setiap Shadow DOM (ruang tertutup di dalam halaman,
// dipakai mis. oleh pemutar video ok.ru). CSS ekstensi tidak menembus Shadow DOM, jadi gaya blur
// juga disuntikkan ke masing-masing.
const roots = [];
const SHADOW_CSS = `
img:not([data-gw-ok]), video:not([data-gw-ok]), canvas:not([data-gw-ok]), svg image:not([data-gw-ok]),
[style*="background-image"]:not([data-gw-ok]), [style*="background:"][style*="url("]:not([data-gw-ok]) {
  filter: blur(28px) grayscale(0.6) !important;
}`;

const SELECTOR = `img, video, canvas, iframe, svg image, ${BG_SELECTOR}`;
function scan(root) {
  root.querySelectorAll?.(SELECTOR).forEach(track);
}
function scanShadowHosts(root) {
  // Cari Shadow DOM yang sudah ada (sekali saat mulai, dan saat potongan halaman baru ditambahkan).
  if (root.shadowRoot) observeRoot(root.shadowRoot);
  root.querySelectorAll?.("*").forEach((el) => el.shadowRoot && observeRoot(el.shadowRoot));
}

function observeRoot(root) {
  if (root.__gwObserved) return;
  root.__gwObserved = true;
  roots.push(root);
  if (root !== document && settings.blurUntilChecked) {
    const st = document.createElement("style");
    st.textContent = SHADOW_CSS;
    root.appendChild(st);
  }
  scan(root);
  new MutationObserver(onMutations).observe(root, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["src", "srcset", "href", "style"],
  });
  if (root !== document) scanShadowHosts(root);
}

function onMutations(muts) {
  for (const m of muts) {
    if (m.type === "attributes") {
      const el = m.target;
      const tag = el.tagName;
      if (tag === "IFRAME") {
        if (m.attributeName === "src") fromPornHost(el.src);
        continue;
      }
      const media = tag === "IMG" || tag === "VIDEO" || tag.toLowerCase() === "image";
      if (media && m.attributeName === "style") continue;
      if (!media) {
        // Hanya peduli bila URL gambar latarnya berubah.
        const url = bgUrl(el);
        if (url === (el.__gwSrc ?? null)) continue;
        if (!url) {
          el.__gwSrc = null;
          if (el.matches(BG_SELECTOR)) markOk(el);
          continue;
        }
      }
      el.removeAttribute(OK);
      el.__gwSrc = undefined;
      io.unobserve(el);
      track(el); // IntersectionObserver akan memanggil pemeriksaan lagi
      continue;
    }
    for (const n of m.addedNodes) {
      if (n.nodeType !== 1) continue;
      track(n);
      scan(n);
      if (n.shadowRoot) observeRoot(n.shadowRoot);
    }
  }
}

function startScanning() {
  observeRoot(document);
  scanShadowHosts(document);
  // shadow-hook.js (berjalan di konteks halaman) memberi tahu setiap kali Shadow DOM baru dibuat.
  document.addEventListener(
    "gw-shadow",
    (e) => {
      const host = e.composedPath()[0];
      if (host?.shadowRoot) observeRoot(host.shadowRoot);
    },
    true
  );
  // Gambar latar yang dipasang lewat file CSS tidak terlihat dari atribut style, jadi dicari dengan
  // "mengambil sampel" titik-titik di layar dan memeriksa elemen di bawahnya.
  setInterval(sampleBackgrounds, 1500);
  setTimeout(sampleBackgrounds, 300);

  // Jaring pengaman untuk Shadow DOM yang terlewat.
  setInterval(() => scanShadowHosts(document), 3000);

  if (settings.checkVideos) {
    setInterval(() => {
      for (const el of inView) if (el.tagName === "VIDEO") checkVideo(el, true);
    }, 2500);
  }
  // Kanvas (mis. pembaca komik/manga online menggambar halaman di <canvas>) diperiksa ulang berkala.
  setInterval(() => {
    for (const el of inView) if (el.tagName === "CANVAS") checkCanvas(el, true);
  }, 3000);
}

function sampleBackgrounds() {
  if (locked || document.visibilityState !== "visible") return;
  const W = innerWidth, H = innerHeight, N = 7;
  const seen = new Set();
  for (let i = 0; i < N; i++)
    for (let j = 0; j < N; j++) {
      const x = ((i + 0.5) * W) / N, y = ((j + 0.5) * H) / N;
      for (const el of document.elementsFromPoint(x, y).slice(0, 6)) {
        if (seen.has(el) || el === document.documentElement || el === document.body) continue;
        seen.add(el);
        if (el.__gwComputedBg !== undefined) continue;
        const tag = el.tagName;
        if (tag === "IMG" || tag === "VIDEO" || tag === "CANVAS") {
          // Cadangan bila situs mematikan MutationObserver/IntersectionObserver: periksa langsung.
          if (!el.__gwSampled) {
            el.__gwSampled = true;
            inView.add(el);
            checkElement(el);
          }
          continue;
        }
        if (tag === "IFRAME") continue;
        const bg = getComputedStyle(el).backgroundImage;
        el.__gwComputedBg = !!bg && bg.includes("url(") && !(el.getAttribute("style") || "").includes("url(");
        if (el.__gwComputedBg) checkBackground(el);
      }
    }
}

function markOk(el) {
  if (!el.hasAttribute(OK)) el.setAttribute(OK, "");
}

// ---------- Penundaan halaman ----------

let pending = 0;
let domReady = document.readyState !== "loading";
let released = false;
document.addEventListener("DOMContentLoaded", () => {
  domReady = true;
  maybeRelease();
});

function begin() {
  pending++;
}
function end() {
  pending = Math.max(0, pending - 1);
  maybeRelease();
}
function maybeRelease() {
  if (released || !IS_TOP) return;
  if (!domReady || pending > 0) return;
  // Beri jeda singkat: gambar baru sering muncul tepat setelah DOM siap.
  clearTimeout(maybeRelease.t);
  maybeRelease.t = setTimeout(() => {
    if (pending === 0) releaseHold();
  }, 200);
}
function releaseHold() {
  if (released) return;
  released = true;
  setClass("gw-hold", false);
}
// Batas maksimal penundaan; setelah itu halaman tampil (gambar yang belum diperiksa tetap ter-blur).
if (IS_TOP) setTimeout(releaseHold, DEFAULT_SETTINGS.holdMaxMs);

async function classify(req) {
  req.mode = settings.aiMode;
  begin();
  try {
    return await send(req);
  } finally {
    end();
  }
}

// ---------- Pemeriksa per jenis elemen ----------

async function checkImage(img) {
  if (locked) return;
  if (!img.complete || !img.naturalWidth) {
    if (img.__gwWaiting) return;
    img.__gwWaiting = true;
    begin();
    const done = (ok) => {
      img.__gwWaiting = false;
      end();
      ok ? checkImage(img) : markOk(img);
    };
    img.addEventListener("load", () => done(true), { once: true });
    img.addEventListener("error", () => done(false), { once: true });
    return;
  }
  const src = img.currentSrc || img.src;
  if (!src || img.__gwSrc === src) return;
  img.__gwSrc = src;

  const shown = Math.min(img.width || img.naturalWidth, img.height || img.naturalHeight);
  const natural = Math.min(img.naturalWidth, img.naturalHeight);
  if (shown < settings.minImageSize && natural < settings.minImageSize) return markOk(img);

  if (fromPornHost(src)) return;
  let req;
  if (src.startsWith("blob:") || src.startsWith("data:")) {
    const dataUrl = src.startsWith("data:") ? src : snapshot(img, img.naturalWidth, img.naturalHeight);
    if (!dataUrl) return markOk(img);
    req = { type: "classify", dataUrl };
  } else {
    req = { type: "classify", url: src };
  }

  let res = await classify(req);
  if (img.__gwSrc !== src) return; // gambar sudah berganti
  if (res?.error && req.url) {
    // Ekstensi gagal mengunduh gambarnya (mis. server menolak). Coba baca langsung dari halaman.
    const dataUrl = snapshot(img, img.naturalWidth, img.naturalHeight);
    if (dataUrl) res = await classify({ type: "classify", dataUrl });
    else if (settings.blurUnreadableVideos) {
      console.debug("[Guard My Eyes] gambar tidak bisa diperiksa, tetap di-blur:", src);
      return; // tetap di-blur
    }
  }
  handleResult(img, res);
}

function bgUrl(el, computed = false) {
  let bg = el.style?.backgroundImage || "";
  if (!bg.includes("url(") && computed) bg = getComputedStyle(el).backgroundImage || "";
  const m = bg.match(/url\(\s*["']?([^"')]+)["']?\s*\)/);
  if (!m) return null;
  try {
    return new URL(m[1], location.href).href;
  } catch {
    return null;
  }
}

async function checkBackground(el) {
  if (locked) return;
  const url = bgUrl(el, el.__gwComputedBg);
  if (!url) return markOk(el);
  if (el.__gwSrc === url) return;
  el.__gwSrc = url;
  if (fromPornHost(url)) return;
  const r = el.getBoundingClientRect();
  if (Math.min(r.width, r.height) < settings.minImageSize) return markOk(el);
  const req = url.startsWith("data:") ? { type: "classify", dataUrl: url } : { type: "classify", url };
  const res = await classify(req);
  if (el.__gwSrc !== url) return;
  handleResult(el, res);
}

async function checkSvgImage(el) {
  if (locked) return;
  const href = el.href?.baseVal || el.getAttribute("href") || el.getAttribute("xlink:href");
  if (!href) return markOk(el);
  let url;
  try {
    url = new URL(href, location.href).href;
  } catch {
    return markOk(el);
  }
  if (el.__gwSrc === url) return;
  el.__gwSrc = url;
  const req = url.startsWith("data:") ? { type: "classify", dataUrl: url } : { type: "classify", url };
  const res = await classify(req);
  if (el.__gwSrc !== url) return;
  handleResult(el, res);
}

async function checkCanvas(cv, periodic = false) {
  if (locked) return;
  if (Math.min(cv.width, cv.height) < settings.minImageSize) return markOk(cv);
  if (cv.__gwTainted) return settings.blurUnreadableVideos ? undefined : markOk(cv);
  const r = cv.getBoundingClientRect();
  if (Math.min(r.width, r.height) < settings.minImageSize) return markOk(cv);
  if (cv.__gwBusy) return;
  cv.__gwBusy = true;
  try {
    const dataUrl = snapshot(cv, cv.width, cv.height);
    if (!dataUrl) {
      cv.__gwTainted = true; // kanvas berisi gambar lintas domain, tidak bisa dibaca
      if (!settings.blurUnreadableVideos) markOk(cv);
      else cv.removeAttribute(OK); // isinya berubah jadi tak terbaca -> blur lagi
      return;
    }
    if (periodic && dataUrl === cv.__gwLast) return; // isinya tidak berubah
    cv.__gwLast = dataUrl;
    handleResult(cv, await classify({ type: "classify", dataUrl }));
  } finally {
    cv.__gwBusy = false;
  }
}

async function checkVideo(video, periodic = false) {
  if (locked || !settings.checkVideos) {
    if (!settings.checkVideos) markOk(video);
    return;
  }
  if (fromPornHost(video.currentSrc || video.src) || fromPornHost(video.poster)) return;
  if (video.readyState < 2 || !video.videoWidth) {
    if (!periodic) video.addEventListener("loadeddata", () => checkVideo(video), { once: true });
    // Selagi video belum siap, periksa gambar poster-nya.
    if (!periodic && video.poster && !video.__gwPoster) {
      video.__gwPoster = true;
      classify({ type: "classify", url: video.poster }).then((res) => {
        const reason = res && !res.error && !res.skip ? evaluate(res) : null;
        if (reason) send({ type: "flag", reason });
      });
    }
    return;
  }
  if (periodic && video.paused && video.hasAttribute(OK)) return;
  if (video.__gwBusy) return;
  video.__gwBusy = true;
  try {
    const dataUrl = video.__gwTainted ? null : snapshot(video, video.videoWidth, video.videoHeight);
    if (dataUrl) return handleResult(video, await classify({ type: "classify", dataUrl }));

    // Video dari server lain yang tidak bisa dibaca halaman -> periksa lewat latar belakang ekstensi.
    video.__gwTainted = true;
    const src = video.currentSrc || video.src;
    if (/^https?:/.test(src)) {
      const res = await classify({ type: "classifyVideo", url: src, time: video.currentTime });
      if (res && !res.error && !res.skip) return handleResult(video, res);
    }
    // Benar-benar tidak bisa diperiksa.
    if (!settings.blurUnreadableVideos) markOk(video); // kalau opsi aktif, video tetap di-blur
  } finally {
    video.__gwBusy = false;
  }
}

function snapshot(el, w, h) {
  try {
    const scale = Math.min(1, 512 / Math.max(w, h));
    const c = document.createElement("canvas");
    c.width = Math.max(1, Math.round(w * scale));
    c.height = Math.max(1, Math.round(h * scale));
    c.getContext("2d").drawImage(el, 0, 0, c.width, c.height);
    return c.toDataURL("image/jpeg", 0.85);
  } catch {
    return null;
  }
}

function hostOf(url) {
  try {
    return new URL(url, location.href).hostname;
  } catch {
    return "";
  }
}
// Gambar/video/iframe yang diambil dari server situs porno -> kunci tanpa menunggu AI.
function fromPornHost(url) {
  if (url && !url.startsWith("data:") && !url.startsWith("blob:") && isPornHost(hostOf(url), settings)) {
    send({ type: "flag", reason: "konten dari situs porno" });
    return true;
  }
  return false;
}

// Penilaian per halaman: beberapa gambar yang masing-masing "agak mencurigakan" (belum melewati ambang)
// tetap menandakan halaman porno, mis. situs penuh thumbnail kecil.
const suspicious = new Set();
function noteSuspicious(el, scores) {
  const ph = (scores.Porn || 0) + (scores.Hentai || 0);
  if (ph >= 0.3 || ph + (scores.Sexy || 0) >= 0.55) {
    suspicious.add(el.__gwSrc || el);
    if (settings.pageSuspiciousCount > 0 && suspicious.size >= settings.pageSuspiciousCount)
      send({ type: "flag", reason: `banyak gambar mencurigakan di halaman ini (${suspicious.size})` });
  }
}

function handleResult(el, res) {
  if (!res || res.error || res.skip) return markOk(el); // gagal diperiksa -> tidak diblokir
  if (res.scores) noteSuspicious(el, res.scores);
  if (res.scores) {
    const top = Object.entries(res.scores).map(([k, v]) => `${k} ${Math.round(v * 100)}%`).join(", ");
    console.debug("[Guard My Eyes]", top, res.faces?.length ? `wajah: ${res.faces.map((f) => f.gender + " " + Math.round(f.p * 100) + "%").join(", ")}` : "", el);
  }
  const reason = evaluate(res);
  if (reason) {
    send({ type: "flag", reason });
  } else {
    markOk(el);
  }
}

function evaluate({ scores = {}, faces = [] }) {
  const s = settings;
  const porn = scores.Porn || 0;
  const hentai = scores.Hentai || 0;
  if (s.detectPorn && hentai >= s.hentaiThreshold) return "konten hentai";
  if (s.detectPorn && (porn >= s.pornThreshold || porn + hentai >= s.pornThreshold)) return "konten porno";
  if (s.detectSexy && (scores.Sexy || 0) >= s.sexyThreshold) return "konten seksi / sugestif";
  if (
    s.detectFemaleFace &&
    faces.some((f) => f.gender === "female" && f.p >= s.femaleThreshold && Math.min(f.w, f.h) >= s.minFaceSize)
  )
    return "wajah wanita";
  return null;
}

// ---------- Mengunci halaman ----------

function lock(reason) {
  if (locked || !IS_TOP) return;
  locked = true;
  // Di aplikasi HP, kunci yang sebenarnya adalah layar native milik aplikasi (tidak bisa dihapus situs).
  if (window.__gwMobile) send({ type: "flag", reason });
  setClass("gw-locked", true);
  releaseHold();

  const stages = [
    { title: "Tulis komitmenmu", text: settings.commitmentText.trim() },
    { title: "Doa Salam Maria", text: settings.prayerText.trim() },
  ].filter((s) => s.text);

  lockScreen = createLockScreen({
    reason,
    stages,
    onFinished: () => send({ type: "finished" }),
  });

  const attach = () => {
    if (!lockScreen.host.isConnected) html.appendChild(lockScreen.host);
  };
  attach();
  // Kalau skrip halaman mencoba menghapus layar peringatan, pasang lagi.
  new MutationObserver(attach).observe(html, { childList: true });

  // Hentikan semua suara/video di halaman.
  const silence = () =>
    [document, ...roots].forEach((r) =>
      r.querySelectorAll("video, audio").forEach((m) => {
        try {
          m.pause();
          m.muted = true;
        } catch {}
      })
    );
  silence();
  setInterval(silence, 1000);

  try {
    document.activeElement?.blur?.();
  } catch {}
}
