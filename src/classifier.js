// Pengklasifikasi AI untuk aplikasi HP: berjalan di WebView tersembunyi.
// Dart mengirim gambar (data URL) -> window.gwClassify(dataUrl) -> {scores, faces}.
import * as tf from "@tensorflow/tfjs";
import { load as loadNsfw } from "nsfwjs/core";
import { MobileNetV2MidModel } from "nsfwjs/models/mobilenet_v2_mid";
import * as faceapi from "@vladmandic/face-api/dist/face-api.esm-nobundle.js";

const MAX_SIDE = 512;
let ready = null;

function init() {
  if (!ready) {
    ready = (async () => {
      try {
        await tf.setBackend("webgl");
      } catch {
        await tf.setBackend("cpu");
      }
      await tf.ready();
      const [nsfw] = await Promise.all([
        loadNsfw("MobileNetV2Mid", { modelDefinitions: [MobileNetV2MidModel] }),
        faceapi.nets.tinyFaceDetector.loadFromUri("./models"),
        faceapi.nets.faceLandmark68TinyNet.loadFromUri("./models"),
        faceapi.nets.ageGenderNet.loadFromUri("./models"),
      ]);
      return nsfw;
    })();
    ready.catch(() => (ready = null));
  }
  return ready;
}

function loadImage(src) {
  return new Promise((ok, err) => {
    const img = new Image();
    img.onload = () => ok(img);
    img.onerror = () => err(new Error("gambar tidak bisa dibuka"));
    img.src = src;
  });
}

function crops(canvas) {
  const { width: w, height: h } = canvas;
  const out = [];
  const cut = (x, y, cw, ch) => {
    const c = document.createElement("canvas");
    c.width = Math.round(cw);
    c.height = Math.round(ch);
    c.getContext("2d").drawImage(canvas, x, y, cw, ch, 0, 0, c.width, c.height);
    out.push(c);
  };
  const side = Math.min(w, h);
  if (w > h * 1.25) for (const x of [0, (w - side) / 2, w - side]) cut(x, 0, side, side);
  else if (h > w * 1.25) for (const y of [0, (h - side) / 2, h - side]) cut(0, y, side, side);
  else {
    const q = side / 2;
    for (const [x, y] of [[0, 0], [w - q, 0], [0, h - q], [w - q, h - q]]) cut(x, y, q, q);
  }
  cut(w * 0.15, h * 0.15, w * 0.7, h * 0.7);
  return out;
}

let queue = Promise.resolve();

window.gwClassify = (dataUrl) => {
  const job = queue.then(async () => {
    const nsfw = await init();
    const img = await loadImage(dataUrl);
    const scale = Math.min(1, MAX_SIDE / Math.max(img.naturalWidth, img.naturalHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(img.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(img.naturalHeight * scale));
    canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
    if (canvas.width < 32 || canvas.height < 32) return { skip: true };

    const toScores = (p) => Object.fromEntries(p.map((x) => [x.className, x.probability]));
    const scores = toScores(await nsfw.classify(canvas, 5));
    const sus = (scores.Porn || 0) + (scores.Hentai || 0) + (scores.Sexy || 0);
    if (sus >= 0.12 && Math.min(canvas.width, canvas.height) >= 96) {
      for (const c of crops(canvas)) {
        const sc = toScores(await nsfw.classify(c, 5));
        for (const k of ["Porn", "Hentai", "Sexy"]) scores[k] = Math.max(scores[k] || 0, sc[k] || 0);
      }
    }
    const det = await faceapi
      .detectAllFaces(canvas, new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.5 }))
      .withFaceLandmarks(true)
      .withAgeAndGender();
    const faces = det.map((d) => ({
      gender: d.gender,
      p: d.genderProbability,
      w: Math.round(d.detection.box.width),
      h: Math.round(d.detection.box.height),
    }));
    return { scores, faces };
  });
  queue = job.catch(() => {});
  return job.catch((e) => ({ error: String(e?.message || e) }));
};

window.gwReady = () => init().then(() => true, (e) => String(e));
init();
