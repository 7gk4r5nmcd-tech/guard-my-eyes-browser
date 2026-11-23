// Membuat folder assets/ untuk aplikasi Flutter dari kode sumber di src/ dan model AI di node_modules.
import * as esbuild from "esbuild";
import fs from "fs";
import { DEFAULT_SETTINGS } from "../src/settings.js";

const common = { bundle: true, platform: "browser", target: ["safari15", "chrome100"], minify: true, legalComments: "none", logLevel: "warning" };
fs.rmSync("assets", { recursive: true, force: true });
fs.mkdirSync("assets/gw", { recursive: true });
fs.mkdirSync("assets/classifier/models", { recursive: true });

// Skrip yang disuntikkan ke setiap halaman.
await esbuild.build({ ...common, entryPoints: ["src/mobile-entry.js"], outfile: "assets/gw/content.js", format: "iife", define: { chrome: "window.__gwChrome" } });
await esbuild.build({ ...common, entryPoints: ["src/shadow-hook.js"], outfile: "assets/gw/shadow-hook.js", format: "iife" });
fs.writeFileSync("assets/gw/defaults.json", JSON.stringify(DEFAULT_SETTINGS, null, 1));

// Halaman AI tersembunyi.
await esbuild.build({ ...common, entryPoints: ["src/classifier.js"], outdir: "assets/classifier", format: "esm", splitting: true, chunkNames: "chunks/[name]-[hash]" });
fs.writeFileSync("assets/classifier/index.html", '<!doctype html><html><head><meta charset="utf-8"></head><body><script type="module" src="classifier.js"></script></body></html>\n');
const modelDir = "node_modules/@vladmandic/face-api/model";
for (const f of fs.readdirSync(modelDir)) {
  if (/^(tiny_face_detector_model|age_gender_model|face_landmark_68_tiny_model)/.test(f)) fs.copyFileSync(`${modelDir}/${f}`, `assets/classifier/models/${f}`);
}
console.log("assets siap:", fs.readdirSync("assets/classifier/chunks").length, "chunk,", fs.readdirSync("assets/classifier/models").length, "file model");
