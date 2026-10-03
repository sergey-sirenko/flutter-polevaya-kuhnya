// Run with Node.js and sharp available (NODE_PATH may point to the runtime bundle).
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'assets/branding/app-icon.png'));
const background = '#305F3D';
async function png(file, size, alpha = false, padding = 0) {
  const dest = path.join(root, file);
  fs.mkdirSync(path.dirname(dest), {recursive: true});
  const inset = Math.round(size * padding);
  let image = sharp(source).resize(size - 2 * inset, size - 2 * inset);
  if (inset) image = image.extend({top: inset, bottom: inset, left: inset, right: inset, background: {r: 0, g: 0, b: 0, alpha: 0}});
  image = alpha ? image.ensureAlpha() : image.flatten({background}).removeAlpha();
  await image.png().toFile(dest);
}
(async () => {
  await png('assets/store/icon-1024.png', 1024);
  await png('assets/store/google-play-icon-512.png', 512, true);
  await png('assets/store/rustore-icon-512.png', 512);
  const feature = fs.readFileSync(path.join(root, 'assets/branding/google-play-feature.svg'), 'utf8')
    .replace(/  <circle[^>]+\/>\s*/g, '')
    .replace('</svg>', `<image x="710" y="134" width="216" height="216" href="data:image/png;base64,${source.toString('base64')}"/></svg>`);
  await sharp(Buffer.from(feature))
    .flatten({background: '#FAF8F5'}).removeAlpha().png()
    .toFile(path.join(root, 'assets/store/google-play-feature-1024x500.png'));
  for (const size of [192, 512]) {
    await png(`web/icons/Icon-${size}.png`, size, true);
    await png(`web/icons/Icon-maskable-${size}.png`, size, false, 0.14);
  }
  await png('web/favicon.png', 32, true);
  for (const [density, size] of Object.entries({mdpi:48, hdpi:72, xhdpi:96, xxhdpi:144, xxxhdpi:192})) {
    await png(`android/app/src/main/res/mipmap-${density}/ic_launcher.png`, size, true);
  }
  await png('android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png', 432, true, 0.2);
  const catalog = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  const contents = JSON.parse(fs.readFileSync(path.join(root, catalog, 'Contents.json')));
  for (const icon of contents.images) {
    if (!icon.filename) continue;
    await png(`${catalog}/${icon.filename}`, Math.round(parseFloat(icon.size) * parseFloat(icon.scale)));
  }
  console.log('Generated store, Android, iOS and Web icons from transparent app-icon.png');
})().catch(error => { console.error(error); process.exitCode = 1; });
