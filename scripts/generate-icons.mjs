/**
 * Generate web and iOS app icons from the approved Chacha bell artwork.
 * Run from any directory: node scripts/generate-icons.mjs (or npm run icons).
 * Keep the original full-bleed artwork in design/app-icon.png; operating
 * systems apply their own corner masks, so no rounding is baked in here.
 */
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = resolve(root, "design/app-icon.png");
const catalogPath = "mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset";
const metadata = await sharp(source).metadata();
if (metadata.width !== metadata.height || metadata.width < 1024) {
  throw new Error("design/app-icon.png must be square and at least 1024px.");
}

async function render(size, maskable = false, alpha = false) {
  // RGB with no alpha is required for the App Store and Apple touch icon.
  const contentSize = maskable ? Math.round(size * 0.82) : size;
  let image = sharp(source)
    .rotate()
    .removeAlpha()
    .toColourspace("srgb")
    .resize(contentSize, contentSize, { kernel: "lanczos3" });
  if (maskable) {
    // Extend the amber edge pixels so the entire bell fits inside the
    // maskable icon's central 80%-diameter safe circle, without a border.
    const before = Math.floor((size - contentSize) / 2);
    const after = size - contentSize - before;
    image = image.extend({
      top: before, bottom: after, left: before, right: after,
      extendWith: "copy",
    });
  }
  // Next.js only accepts RGBA PNGs inside favicon.ico.
  return (alpha ? image.ensureAlpha() : image).png().toBuffer();
}

async function save(path, data) {
  await writeFile(resolve(root, path), data);
  console.log(`wrote ${path}`);
}

for (const [path, size, maskable] of [
  ["public/icon-192.png", 192, false],
  ["public/icon-512.png", 512, false],
  ["public/icon-maskable-512.png", 512, true],
  ["public/apple-icon.png", 180, false],
]) {
  await save(path, await render(size, maskable));
}

// ICO supports embedded PNGs, allowing the favicon to use the same source
// without introducing a separate image conversion dependency.
const faviconSizes = [16, 32, 48, 64];
const faviconImages = await Promise.all(faviconSizes.map((size) => render(size, false, true)));
const header = Buffer.alloc(6 + 16 * faviconImages.length);
header.writeUInt16LE(1, 2); // ICO image type
header.writeUInt16LE(faviconImages.length, 4);
let offset = header.length;
faviconImages.forEach((data, index) => {
  const entry = 6 + index * 16;
  header[entry] = faviconSizes[index];
  header[entry + 1] = faviconSizes[index];
  header.writeUInt16LE(1, entry + 4); // color planes
  header.writeUInt16LE(32, entry + 6); // bits per pixel
  header.writeUInt32LE(data.length, entry + 8);
  header.writeUInt32LE(offset, entry + 12);
  offset += data.length;
});
await save("app/favicon.ico", Buffer.concat([header, ...faviconImages]));

const catalog = JSON.parse(await readFile(resolve(root, catalogPath, "Contents.json"), "utf8"));
const icons = new Map();
for (const { filename, size, scale } of catalog.images) {
  if (!filename) continue;
  const pixels = Number.parseFloat(size) * Number.parseFloat(scale);
  if (!Number.isInteger(pixels)) throw new Error(`Invalid icon size: ${filename}`);
  if (icons.has(filename) && icons.get(filename) !== pixels) {
    throw new Error(`Conflicting catalog sizes: ${filename}`);
  }
  icons.set(filename, pixels);
}
for (const [filename, size] of icons) {
  await save(`${catalogPath}/${filename}`, await render(size));
}
