$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repoRoot
try {
    & flutter build web --release --no-pub `
        '--dart-define=APP_ENV=test' `
        '--dart-define=API_BASE_URL=https://hleb-sol.su/Zakaz_http/hs/Obmen/' `
        '--dart-define=DATA_BASE_URL=https://obedmoscow.ru/data/'
    if ($LASTEXITCODE -ne 0) { throw 'Test Web build failed.' }
    Write-Output 'build/web is ready. Deploy to flutter-test.obedmoscow.ru over SSH for user testing.'
}
finally { Pop-Location }
