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

window.chrome = window.chrome || {};
window.__gwChrome = {
  runtime: {
    id: "gw-app",
    sendMessage: async (msg) => {
      await platformReady;
      try {
        return await window.flutter_inappwebview.callHandler("gw", msg);
      } catch (e) {
        return { error: String(e) };
      }
    },
    onMessage: { addListener: (fn) => listeners.push(fn) },
  },
  storage: {
    sync: { get: async (defs) => ({ ...(defs || {}), ...(window.__gwSettings || {}) }) },
  },
};
// Dart memanggil ini, mis. __gwDispatch({type:"lock", reason:"..."}).
window.__gwDispatch = (msg) => listeners.forEach((fn) => fn(msg));
