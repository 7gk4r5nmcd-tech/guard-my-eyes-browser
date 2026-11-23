// Berjalan di konteks halaman (world: MAIN) sejak awal.
// Membuat semua Shadow DOM "terbuka" agar bisa diperiksa ekstensi, lalu memberi tahu content script.
(() => {
  if (Element.prototype.attachShadow.__gw) return;
  const orig = Element.prototype.attachShadow;
  const patched = function (init) {
    const root = orig.call(this, { ...init, mode: "open" });
    const host = this;
    queueMicrotask(() => host.dispatchEvent(new CustomEvent("gw-shadow", { bubbles: true, composed: true })));
    return root;
  };
  patched.__gw = true;
  Element.prototype.attachShadow = patched;
})();
