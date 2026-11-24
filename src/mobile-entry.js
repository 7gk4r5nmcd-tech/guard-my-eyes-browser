import "./mobile-shim.js";
import rawCss from "./mobile.css";
import { DEFAULT_SETTINGS, isWhitelisted } from "./settings.js";

// Situs tidak boleh bisa mematikan blur dengan menambahkan kelas "gw-noblur" ke <html>,
// jadi di HP keputusan blur diambil di sini, dari pengaturan aplikasi.
const cfg = { ...DEFAULT_SETTINGS, ...(window.__gwSettings || {}) };
const blurOn = cfg.blurUntilChecked !== false && !isWhitelisted(location.hostname, cfg.whitelist || "");
const css = blurOn ? rawCss.split("html:not(.gw-noblur) ").join("") : rawCss;

// Di ekstensi laptop CSS dipasang oleh Chrome; di aplikasi HP kita pasang sendiri,
// dan pasang ulang bila situs menghapusnya.
function injectCss() {
  const root = document.documentElement;
  let st = document.getElementById("__gw_css");
  if (!st) {
    st = document.createElement("style");
    st.id = "__gw_css";
    st.textContent = css;
  }
  if (st.parentNode !== root) root.appendChild(st);
  if (st.textContent !== css) st.textContent = css;
}

// Di sebagian WebView, skrip "document start" bisa berjalan sebelum <html> ada. Tunggu dulu.
function start() {
  injectCss();
  new MutationObserver(injectCss).observe(document.documentElement, { childList: true, subtree: false, characterData: true });
  require("./content.js");
}
if (document.documentElement) start();
else {
  const mo = new MutationObserver(() => {
    if (document.documentElement) {
      mo.disconnect();
      start();
    }
  });
  mo.observe(document, { childList: true });
}
