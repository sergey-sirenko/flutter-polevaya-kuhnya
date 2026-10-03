$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repoRoot
try {
    & flutter build web --release --no-pub `
        '--dart-define=APP_ENV=test' `
        '--dart-define=API_BASE_URL=https://hleb-sol.su/Zakaz_http/hs/Obmen/' `
        '--dart-define=DATA_BASE_URL=https://obedmoscow.ru/data/' `
        '--dart-define=APP_VERSION_URL=https://flutter-test.obedmoscow.ru/version.json'
    if ($LASTEXITCODE -ne 0) { throw 'Test Web build failed.' }
    & python (Join-Path $PSScriptRoot 'check_web_version_policy.py') `
        --version (Join-Path $repoRoot 'build/web/version.json') `
        --pubspec (Join-Path $repoRoot 'pubspec.yaml')
    if ($LASTEXITCODE -ne 0) { throw 'build/web/version.json failed the test policy check.' }
    Write-Output 'build/web is ready. Deploy to flutter-test.obedmoscow.ru over SSH for user testing.'
}
finally { Pop-Location }
