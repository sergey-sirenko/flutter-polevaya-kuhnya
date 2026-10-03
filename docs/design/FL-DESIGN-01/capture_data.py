"""Freeze public menu and unmodified photos for the three local prototypes."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import sys
import urllib.request
from datetime import datetime, timezone, timedelta
import subprocess

ROOT = Path(__file__).resolve().parent
SOURCE = 'https://obedmoscow.ru/data/'

def read(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Connection': 'close'})
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read()

def main():
    raw = (ROOT / 'menu-snapshot.json').read_bytes() if '--use-saved' in sys.argv else read(SOURCE + 'dishes.json')
    data = json.loads(raw.decode('utf-8-sig'))
    assert any(d['date'] == '2026-10-05' for w in data['weeks'] for d in w['days'])
    (ROOT / 'menu-snapshot.json').write_bytes(raw)
    (ROOT / 'menu-data.js').write_text('window.MENU_SNAPSHOT = ' + json.dumps(data, ensure_ascii=False) + ';\n', encoding='utf-8')
    images = {}
    for week in data['weeks']:
        for day in week['days']:
            for category in day['categories']:
                path = category.get('categoryimagePath') or category.get('categoryImagePath')
                if path:
                    images.setdefault(path, set()).add(category.get('photo_version') or 'legacy')
                for dish in category['dishes']:
                    path = dish.get('imagePath')
                    if path:
                        images.setdefault(path, set()).add(dish.get('photo_version') or 'legacy')
    folder = ROOT / 'images'
    folder.mkdir(exist_ok=True)
    initial = next(d for w in data['weeks'] for d in w['days'] if d['date'] == '2026-10-05')
    priority = {d.get('imagePath') for c in initial['categories'] for d in c['dishes']}
    priority.update(c.get('categoryimagePath') or c.get('categoryImagePath') for c in initial['categories'])
    items = sorted(images.items(), key=lambda item: (item[0] not in priority, item[0]))
    records = []
    def download(item):
        path, versions = item
        assert all(c.isalnum() or c in '_-' for c in path)
        url = SOURCE + 'pictures/' + path + '.jpg'
        target = folder / (path + '.jpg')
        result = {'path': path, 'source': url, 'photoVersions': sorted(versions)}
        try:
            if '--use-saved' in sys.argv and target.exists():
                content = target.read_bytes()
            else:
                download_process = subprocess.run(['curl.exe','--fail','--location','--silent','--show-error','--connect-timeout','10','--max-time','30','--retry','1',url],capture_output=True,check=True)
                content = download_process.stdout
            if not content.startswith(b'\xff\xd8'):
                raise ValueError('Response is not JPEG')
            target.write_bytes(content)
            result.update(bytes=len(content), sha256=hashlib.sha256(content).hexdigest(), status='ok')
        except Exception as error:
            result.update(status='unavailable', error=str(error))
        return result
    print(f'Public snapshot: {len(images)} unique original photos', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for index, result in enumerate(pool.map(download, items), 1):
            records.append(result)
            if index % 50 == 0:
                print(f'Photos: {index}/{len(images)}', flush=True)
    logo = ROOT.parents[2] / 'assets/branding/app-logo-cb1bbbb6c0df.png'
    shutil.copyfile(logo, ROOT / 'logo.png')
    manifest = {
        'capturedAt': datetime.fromtimestamp((ROOT / 'menu-snapshot.json').stat().st_mtime, timezone(timedelta(hours=3))).isoformat(),
        'menuSource': SOURCE + 'dishes.json', 'menuSHA256': hashlib.sha256(raw).hexdigest(),
        'initialDate': '2026-10-05',
        'logoSource': 'assets/branding/app-logo-cb1bbbb6c0df.png',
        'logoSHA256': hashlib.sha256(logo.read_bytes()).hexdigest(),
        'photos': records,
    }
    (ROOT / 'sources.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    failed = [r['path'] for r in records if r['status'] != 'ok']
    print(json.dumps({'photos': len(records), 'bytes': sum(r.get('bytes', 0) for r in records), 'unavailable': failed}, ensure_ascii=False), flush=True)

if __name__ == '__main__':
    main()
