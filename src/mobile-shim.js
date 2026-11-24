// Pengganti API chrome.* untuk aplikasi HP (flutter_inappwebview).
// content.js ekstensi dipakai ulang apa adanya; pesan diteruskan ke Dart lewat callHandler("gw").
window.__gwMobile = true;
const listeners = [];
const platformReady = new Promise((ok) => {
  if (window.flutter_inappwebview?.callHandler) return ok();
  window.addEventListener("flutterInAppWebViewPlatformReady", () => ok(), { once: true });
  // Cadangan bila event terlewat.
  const t = setInterval(() => window.flutter_inappwebview?.callHandler && (clearInterval(t), ok()), 100);
});

// Simpan referensi jembatan sedini mungkin, supaya skrip situs yang menimpa
// window.flutter_inappwebview.callHandler belakangan tidak bisa memalsukan hasil.
let bridge = null;
const grab = () => {
  const fi = window.flutter_inappwebview;
  if (!bridge && fi?.callHandler) bridge = fi.callHandler.bind(fi);
};
grab();
platformReady.then(grab);

const lockProp = (name, value) => {
  try {
    Object.defineProperty(window, name, { value, writable: false, configurable: false });
  } catch {
    window[name] = value;
  }
};

window.chrome = window.chrome || {};
lockProp("__gwChrome", Object.freeze({
  runtime: Object.freeze({
    id: "gw-app",
    sendMessage: async (msg) => {
      await platformReady;
      grab();
      try {
        return await bridge("gw", msg);
      } catch (e) {
        return { error: String(e) };
      }
    },
    onMessage: Object.freeze({ addListener: (fn) => listeners.push(fn) }),
  }),
  storage: Object.freeze({
    sync: Object.freeze({ get: async (defs) => ({ ...(defs || {}), ...settings }) }),
  }),
}));
// Pengaturan dari aplikasi dibekukan supaya situs tidak bisa mematikannya.
const settings = Object.freeze({ ...(window.__gwSettings || {}) });
// Dart memanggil ini, mis. __gwDispatch({type:"lock", reason:"..."}).
lockProp("__gwDispatch", (msg) => listeners.forEach((fn) => fn(msg)));
