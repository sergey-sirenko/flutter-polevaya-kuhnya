"""Convert browser JPEG captures to PNG and assemble comparison sheets.

Requires Pillow; the Codex bundled Python runtime includes it.
Screenshots are captured through cua_repl, never redrawn.
"""
from pathlib import Path
import json
import hashlib
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
CAPTURES = ROOT.parents[2] / 'build/FL-DESIGN-01-captures'
PREVIEWS = ROOT / 'previews'
LABELS = ['1. Белая кухня', '2. Тёплый обед', '3. Зелёный стандарт']

def main():
    PREVIEWS.mkdir(exist_ok=True)
    captures = json.loads((CAPTURES / 'captures.json').read_text(encoding='utf-8'))
    assert len(captures) == 12
    for capture in captures:
        name = capture['name']
        image = Image.open(CAPTURES / (name + '.jpg')).convert('RGB')
        # The browser API scales captures slightly. Restore the requested
        # viewport dimensions without cropping or redrawing any page content.
        assert 0 <= capture['width'] - image.width <= 20, (name, image.size)
        assert abs(image.width/image.height-capture['width']/capture['height']) < .01
        capture['nativeCaptureWidth'], capture['nativeCaptureHeight'] = image.size
        image = image.resize((capture['width'],capture['height']),Image.Resampling.LANCZOS)
        capture['pngWidth'], capture['pngHeight'] = image.size
        image.save(PREVIEWS / (name + '.png'), optimize=True)
    font_path = Path('C:/Windows/Fonts/arial.ttf')
    font = ImageFont.truetype(str(font_path), 22) if font_path.exists() else ImageFont.load_default()
    for page in ['home', 'menu']:
        sheet = Image.new('RGB', (1230, 920), '#f2f5ef')
        draw = ImageDraw.Draw(sheet)
        for index, label in enumerate(LABELS):
            x = 15 + index * 405
            draw.text((x + 8, 16), label, fill='#25382a', font=font)
            image = Image.open(PREVIEWS / f'{index+1}-{page}-mobile.png')
            sheet.paste(image, (x, 56))
        sheet.save(ROOT / f'comparison-{page}.png', optimize=True)
    sources = json.loads((ROOT / 'sources.json').read_text(encoding='utf-8'))
    (ROOT / 'previews.json').write_text(json.dumps(captures, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    assert len(sources['photos']) == 436
    for record in sources['photos']:
        path = ROOT / 'images' / (record['path'] + '.jpg')
        assert record['status'] == 'ok'
        assert hashlib.sha256(path.read_bytes()).hexdigest() == record['sha256']
        with Image.open(path) as photo:
            photo.verify()
    assert hashlib.sha256((ROOT / 'menu-snapshot.json').read_bytes()).hexdigest() == sources['menuSHA256']
    assert hashlib.sha256((ROOT / 'logo.png').read_bytes()).hexdigest() == sources['logoSHA256']
    print(json.dumps({'previews':12,'comparisonSheets':2,'originalPhotosVerified':len(sources['photos']),'snapshotSHA256':sources['menuSHA256']},ensure_ascii=False))

if __name__ == '__main__':
    main()
