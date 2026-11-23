// Layar peringatan + tantangan mengetik ala Monkeytype.

const CSS = `
:host { all: initial; }
.wrap {
  position: fixed; inset: 0; z-index: 2147483647;
  background: #323437; color: #d1d0c5;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  font-family: "Roboto Mono", "JetBrains Mono", "Fira Code", Consolas, "Courier New", monospace;
  padding: 32px; box-sizing: border-box; overflow: auto;
  -webkit-user-select: none; user-select: none;
}
.top { text-align: center; margin-bottom: 36px; max-width: 900px; }
.badge {
  display: inline-block; padding: 6px 14px; border-radius: 6px;
  background: #ca4754; color: #fff; font-size: 13px; letter-spacing: .08em; text-transform: uppercase;
}
h1 { font-size: 28px; font-weight: 600; margin: 16px 0 8px; color: #e2b714; }
.reason { font-size: 14px; color: #8b8d90; }
.stage { width: 100%; max-width: 920px; }
.stage-head { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 14px; }
.stage-title { font-size: 16px; color: #e2b714; }
.stage-count { font-size: 14px; color: #646669; }
.text {
  font-size: 24px; line-height: 1.65; letter-spacing: .01em;
  display: flex; flex-wrap: wrap; position: relative; outline: none;
}
.word { display: inline-flex; white-space: pre; }
.ch { position: relative; color: #646669; transition: color .05s; }
.ch.ok { color: #d1d0c5; }
.ch.bad { color: #ca4754; }
.ch.bad.space { background: rgba(202,71,84,.35); border-radius: 2px; }
.ch.caret::before {
  content: ""; position: absolute; left: -1px; top: 12%; height: 76%; width: 2px;
  background: #e2b714; border-radius: 1px; animation: blink 1s step-end infinite;
}
.ch.caret.typing::before { animation: none; }
.end-caret { width: 0; position: relative; }
@keyframes blink { 50% { opacity: 0; } }
.stats { margin-top: 24px; display: flex; gap: 28px; font-size: 14px; color: #646669; }
.stats b { color: #e2b714; font-weight: 500; font-size: 20px; display: block; }
.hint { margin-top: 36px; font-size: 13px; color: #646669; text-align: center; }
.hint kbd { background: #2c2e31; color: #d1d0c5; border-radius: 4px; padding: 2px 6px; font-family: inherit; }
.done { text-align: center; }
.done h2 { font-size: 34px; color: #e2b714; margin: 0 0 12px; }
.done p { color: #d1d0c5; font-size: 16px; margin: 6px 0; }
.done .small { color: #646669; font-size: 13px; margin-top: 18px; }
.flash { animation: flash .35s ease; }
.mob {
  position: fixed; left: 0; bottom: 0; width: 100%; height: 40px; z-index: 2147483647;
  opacity: 0; font-size: 16px; border: 0; padding: 0; resize: none; caret-color: transparent;
}
@media (max-width: 700px) {
  .wrap { justify-content: flex-start; padding: 28px 18px 120px; }
  .top { margin-bottom: 20px; }
  h1 { font-size: 22px; }
  .text { font-size: 19px; line-height: 1.6; }
  .stats { gap: 18px; }
  .hint { margin-top: 20px; }
}
@keyframes flash { 0% { background: rgba(226,183,20,.18);} 100% { background: transparent; } }
`;

export function createLockScreen({ reason, stages, onFinished }) {
  const host = document.createElement("gw-lock");
  const root = host.attachShadow({ mode: "closed" });
  const MOBILE = !!window.__gwMobile;
  root.innerHTML = `<style>${CSS}</style><div class="wrap" tabindex="-1"></div>` +
    (MOBILE ? `<textarea class="mob" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" enterkeyhint="done"></textarea>` : "");
  const wrap = root.querySelector(".wrap");
  const ta = root.querySelector(".mob");

  let stageIndex = 0;
  let typed = "";
  let startedAt = 0;
  let keystrokes = 0;
  let correctKeystrokes = 0;
  let typingTimer = null;
  let finished = false;

  function renderStage() {
    const stage = stages[stageIndex];
    wrap.innerHTML = `
      <div class="top">
        <span class="badge">Konten diblokir</span>
        <h1>Berhenti sejenak.</h1>
        <div class="reason">Terdeteksi: ${escapeHtml(reason)}. Ketik ulang teks di bawah untuk keluar dari halaman ini.</div>
      </div>
      <div class="stage">
        <div class="stage-head">
          <span class="stage-title">${escapeHtml(stage.title)}</span>
          <span class="stage-count">${stageIndex + 1} / ${stages.length}</span>
        </div>
        <div class="text"></div>
        <div class="stats">
          <div><b class="wpm">0</b>wpm</div>
          <div><b class="acc">100%</b>akurasi</div>
          <div><b class="prog">0%</b>selesai</div>
        </div>
      </div>
      <div class="hint">${MOBILE
        ? "Ketuk layar untuk memunculkan keyboard &nbsp;•&nbsp; hapus untuk memperbaiki &nbsp;•&nbsp; tempel (paste) tidak bisa"
        : "Mulai mengetik di mana saja &nbsp;•&nbsp; <kbd>Backspace</kbd> untuk memperbaiki &nbsp;•&nbsp; <kbd>Ctrl</kbd>+<kbd>Backspace</kbd> hapus satu kata &nbsp;•&nbsp; copy-paste tidak bisa"}</div>
    `;
    renderText();
  }

  function renderText() {
    const target = stages[stageIndex].text;
    const box = wrap.querySelector(".text");
    if (!box) return;
    const frag = document.createDocumentFragment();
    let word = document.createElement("span");
    word.className = "word";
    for (let i = 0; i < target.length; i++) {
      const ch = target[i];
      const span = document.createElement("span");
      span.className = "ch";
      span.textContent = ch;
      if (i < typed.length) span.classList.add(typed[i] === ch ? "ok" : "bad");
      if (ch === " ") span.classList.add("space");
      if (i === typed.length) {
        span.classList.add("caret");
        if (typingTimer) span.classList.add("typing");
      }
      word.appendChild(span);
      if (ch === " ") {
        frag.appendChild(word);
        word = document.createElement("span");
        word.className = "word";
      }
    }
    if (typed.length >= target.length) {
      const end = document.createElement("span");
      end.className = "ch caret end-caret";
      end.textContent = "​";
      word.appendChild(end);
    }
    frag.appendChild(word);
    box.replaceChildren(frag);

    const correctChars = [...typed].filter((c, i) => c === target[i]).length;
    const minutes = startedAt ? (Date.now() - startedAt) / 60000 : 0;
    const wpm = minutes > 0.02 ? Math.round(correctChars / 5 / minutes) : 0;
    const acc = keystrokes ? Math.round((correctKeystrokes / keystrokes) * 100) : 100;
    wrap.querySelector(".wpm").textContent = wpm;
    wrap.querySelector(".acc").textContent = acc + "%";
    wrap.querySelector(".prog").textContent = Math.floor((correctChars / target.length) * 100) + "%";
  }

  function renderDone() {
    const minutes = (Date.now() - startedAt) / 60000;
    const totalChars = stages.reduce((n, s) => n + s.text.length, 0);
    const wpm = minutes > 0 ? Math.round(totalChars / 5 / minutes) : 0;
    const acc = keystrokes ? Math.round((correctKeystrokes / keystrokes) * 100) : 100;
    wrap.innerHTML = `
      <div class="done">
        <h2>Amin. 🙏</h2>
        <p>Kamu memilih untuk tidak menyerah. Itu kemenangan.</p>
        <p style="color:#646669">${wpm} wpm • akurasi ${acc}%</p>
        <p class="small">Halaman ini akan ditutup…</p>
      </div>`;
  }

  function onKey(e) {
    if (finished || MOBILE) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    const target = stages[stageIndex].text;

    if (e.key === "Backspace") {
      if (e.ctrlKey || e.altKey || e.metaKey) {
        let i = typed.length;
        while (i > 0 && typed[i - 1] === " ") i--;
        while (i > 0 && typed[i - 1] !== " ") i--;
        typed = typed.slice(0, i);
      } else {
        typed = typed.slice(0, -1);
      }
    } else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey) {
      if (typed.length >= target.length) return;
      if (!startedAt) startedAt = Date.now();
      keystrokes++;
      if (e.key === target[typed.length]) correctKeystrokes++;
      typed += e.key;
    } else {
      return;
    }
    afterChange();
  }

  function afterChange() {
    const target = stages[stageIndex].text;
    clearTimeout(typingTimer);
    typingTimer = setTimeout(() => {
      typingTimer = null;
      renderText();
    }, 500);
    renderText();

    if (typed === target) {
      finished = true;
      setTimeout(() => {
        if (stageIndex < stages.length - 1) {
          stageIndex++;
          typed = "";
          if (ta) ta.value = "";
          finished = false;
          renderStage();
          wrap.querySelector(".stage")?.classList.add("flash");
        } else {
          renderDone();
          setTimeout(onFinished, 2500);
        }
      }, 450);
    }
  }

  // HP: keyboard layar hanya muncul bila ada kolom teks, jadi pakai textarea tak terlihat.
  if (ta) {
    const focus = () => ta.focus({ preventScroll: true });
    wrap.addEventListener("click", focus);
    wrap.addEventListener("touchend", focus);
    ta.addEventListener("input", () => {
      const target = stages[stageIndex].text;
      const v = ta.value;
      if (finished) return void (ta.value = typed);
      // Tambahan banyak huruf sekaligus = tempel/saran keyboard -> ditolak.
      if (v.length > typed.length + 2) return void (ta.value = typed);
      for (let i = typed.length; i < Math.min(v.length, target.length); i++) {
        if (!startedAt) startedAt = Date.now();
        keystrokes++;
        if (v[i] === target[i]) correctKeystrokes++;
      }
      typed = v.slice(0, target.length);
      ta.value = typed;
      afterChange();
    });
    setTimeout(focus, 300);
  }

  renderStage();
  return { host, onKey };
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}
