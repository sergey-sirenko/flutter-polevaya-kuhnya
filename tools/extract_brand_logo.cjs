// Remove a neutral checkerboard connected to the outside, keeping the colored logo.
// Run: node tools/extract_brand_logo.cjs <source.png> <destination.png>
const sharp = require('sharp');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const [input, output] = process.argv.slice(2);
  if (!input || !output) throw new Error('Provide source and destination PNG paths.');
  const {data, info} = await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  const {width, height} = info;
  const count = width * height;
  const exterior = new Uint8Array(count);
  const queue = new Uint32Array(count);
  let head = 0, tail = 0;
  function visit(p) {
    if (exterior[p]) return;
    const i = p * 4;
    const spread = Math.max(data[i], data[i + 1], data[i + 2]) - Math.min(data[i], data[i + 1], data[i + 2]);
    if (spread > 25) return;
    exterior[p] = 1;
    queue[tail++] = p;
  }
  for (let x = 0; x < width; x++) { visit(x); visit((height - 1) * width + x); }
  for (let y = 0; y < height; y++) { visit(y * width); visit(y * width + width - 1); }
  while (head < tail) {
    const p = queue[head++], x = p % width;
    if (x) visit(p - 1);
    if (x + 1 < width) visit(p + 1);
    if (p >= width) visit(p - width);
    if (p + width < count) visit(p + width);
  }
  let left = width, top = height, right = 0, bottom = 0;
  for (let p = 0; p < count; p++) {
    if (exterior[p]) { data.fill(0, p * 4, p * 4 + 4); continue; }
    const x = p % width, y = Math.floor(p / width);
    left = Math.min(left, x); right = Math.max(right, x);
    top = Math.min(top, y); bottom = Math.max(bottom, y);
  }
  if (!tail || right <= left || bottom <= top) throw new Error('No isolated logo found.');
  const w = right - left + 1, h = bottom - top + 1;
  const side = Math.max(w, h) + 2 * Math.ceil(Math.max(w, h) * 0.04);
  fs.mkdirSync(path.dirname(path.resolve(output)), {recursive: true});
  const square = await sharp(data, {raw: {width, height, channels: 4}})
    .extract({left, top, width: w, height: h})
    .extend({left: Math.floor((side - w) / 2), right: Math.ceil((side - w) / 2), top: Math.floor((side - h) / 2), bottom: Math.ceil((side - h) / 2), background: {r: 0, g: 0, b: 0, alpha: 0}})
    .png().toBuffer();
  await sharp(square).resize(1024, 1024).png().toFile(output);
  console.log(JSON.stringify({input, output, removedPixels: tail, bounds: {left, top, w, h}, size: 1024}));
})().catch(error => { console.error(error); process.exitCode = 1; });
