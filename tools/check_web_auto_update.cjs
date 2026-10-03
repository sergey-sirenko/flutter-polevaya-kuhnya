// Bootstrap проверяется без запуска сети/сервера и без подмены исполняемого кода.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('web/flutter_bootstrap.js', 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '')
  .replace('{{flutter_service_worker_version}}', JSON.stringify('build-58'));
for (const release of [null, '0.1.0+59', 'invalid', 'https://other.example/']) {
  const config = { builds: [{ mainJsPath: 'main.dart.js' }] };
  let loaded = 0;
  const search = release ? '?_app_update=' + encodeURIComponent(release) : '';
  vm.runInNewContext(source, {
    URL, URLSearchParams, window: { location: { search } },
    document: { baseURI: 'https://flutter-test.obedmoscow.ru/' },
    _flutter: { buildConfig: config, loader: { load: () => loaded++ } },
  });
  assert.equal(loaded, 1);
  const path = new URL(config.builds[0].mainJsPath);
  assert.equal(path.searchParams.get('_app_code'), 'build-58');
  if (release === '0.1.0+59') {
    assert.equal(path.origin, 'https://flutter-test.obedmoscow.ru');
    assert.equal(path.pathname, '/main.dart.js');
    assert.equal(path.searchParams.get('_app_update'), release);
  } else assert.equal(path.searchParams.get('_app_update'), null);
}
assert.match(fs.readFileSync('web/index.html', 'utf8'), /\{\{flutter_bootstrap_js\}\}/);
assert.doesNotMatch(source, /serviceWorkerSettings/);
console.log('Bootstrap: 4 URL cases, inline loader, no worker registration: OK');
if (process.argv.includes('--built')) {
  const index = fs.readFileSync('build/web/index.html', 'utf8');
  assert.doesNotMatch(index, /\{\{flutter_/);
  assert.ok(/const compiledStamp = String\("\d+"/.test(index), 'generated stamp must be expanded');
  assert.match(index, /_app_code/);
  console.log('Built index: inline bootstrap, generated stamp, no unresolved tokens: OK');
}
