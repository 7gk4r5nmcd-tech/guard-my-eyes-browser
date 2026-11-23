import "./mobile-shim.js";
// Di sebagian WebView, skrip "document start" bisa berjalan sebelum <html> ada. Tunggu dulu.
function start() {
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
