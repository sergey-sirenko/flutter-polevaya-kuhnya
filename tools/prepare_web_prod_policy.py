"""Prepare prod policy and inventory of a built, accepted source release."""
import argparse
import hashlib
import json
import pathlib
import re

from check_web_version_policy import check_file


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--pubspec', required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.commit):
        parser.error('Full accepted source SHA required.')
    root = pathlib.Path(args.output)
    version, build = check_file(root / 'version.json', pathlib.Path(args.pubspec))
    policy = json.loads((root / 'version.json').read_text(encoding='utf-8'))
    policy['policy']['environment'] = 'prod'
    policy['policy']['releases']['web']['url'] = 'https://obedmoscow.ru/'
    # Preserve 0.1.0+1 and unpublished mobile channels from validated test policy.
    (root / 'version.json').write_text(json.dumps(policy, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for name in ('index.html', 'robots.txt', 'sitemap.xml'):
        content = (root / name).read_text(encoding='utf-8')
        if 'https://new.obedmoscow.ru/' in content or 'https://obedmoscow.ru/' not in content:
            raise ValueError(f'Production SEO origin does not match obedmoscow.ru: {name}.')
    if not (root / 'service-worker.js').is_file():
        raise ValueError('Legacy worker retirement file missing.')
    manifest_path = root / 'release-manifest.json'
    files = [
        {'path': p.relative_to(root).as_posix(), 'size': p.stat().st_size,
         'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
        for p in sorted(root.rglob('*')) if p.is_file() and p != manifest_path
    ]
    manifest = {'sourceCommit': args.commit, 'version': version, 'build': build,
                'environment': 'prod', 'files': files}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared prod {version}+{build}: {len(files)} files; not published.')


if __name__ == '__main__':
    main()
