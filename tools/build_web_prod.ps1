param(
    [Parameter(Mandatory = $true)][string]$AcceptedCommit
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repoRoot
try {
    $head = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $AcceptedCommit -notmatch '^[0-9a-f]{40}$' -or $head -ne $AcceptedCommit) {
        throw 'Use the full accepted source commit checked out at HEAD.'
    }
    $dirty = & git status --porcelain --untracked-files=all
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Production build requires a clean committed checkout.' }
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Locked dependency resolution failed.' }
    & flutter build web --release --no-pub '--output=build/web-prod' `
        '--dart-define=APP_ENV=prod' `
        '--dart-define=API_BASE_URL=https://hleb-sol.su/Zakaz_http/hs/Obmen/' `
        '--dart-define=DATA_BASE_URL=https://obedmoscow.ru/data/' `
        '--dart-define=APP_VERSION_URL=https://obedmoscow.ru/version.json'
    if ($LASTEXITCODE -ne 0) { throw 'Production Web build failed.' }
    & python (Join-Path $PSScriptRoot 'prepare_web_prod_policy.py') `
        --output (Join-Path $repoRoot 'build/web-prod') `
        --pubspec (Join-Path $repoRoot 'pubspec.yaml') --commit $AcceptedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Production policy/manifest preparation failed.' }
    Write-Output 'Production package: build/web-prod. Publish only after test acceptance and backup.'
}
finally { Pop-Location }
