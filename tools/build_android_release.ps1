param(
    [string]$KeysDir = (Join-Path $env:USERPROFILE 'PolevayaKuhnyaKeys')
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$uploadFile = Join-Path $KeysDir 'upload.p12'
$appFile = Join-Path $KeysDir 'app-signing.p12'
if (-not (Test-Path -LiteralPath $uploadFile) -or -not (Test-Path -LiteralPath $appFile)) {
    throw 'Не найдены оба keystore. См. docs/android-signing-recovery.md.'
}

function Read-KeyPassword([string]$Label) {
    $secure = Read-Host "Пароль $Label (не показывается)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Invoke-SignedBuild([string]$Alias, [string]$Keystore, [string]$Target) {
    $password = Read-KeyPassword $Alias
    try {
        [Environment]::SetEnvironmentVariable('POLEVAYA_KEYSTORE_PATH', $Keystore, 'Process')
        [Environment]::SetEnvironmentVariable('POLEVAYA_KEYSTORE_PASSWORD', $password, 'Process')
        [Environment]::SetEnvironmentVariable('POLEVAYA_KEY_ALIAS', $Alias, 'Process')
        [Environment]::SetEnvironmentVariable('POLEVAYA_KEY_PASSWORD', $password, 'Process')
        $password = $null
        & keytool -list -keystore $Keystore -storetype PKCS12 -alias $Alias `
            -storepass:env POLEVAYA_KEYSTORE_PASSWORD | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Пароль или keystore $Alias неверен." }
        # Flutter 3.47 may leave integration_test in GeneratedPluginRegistrant
        # with --no-pub even though release excludes this dev dependency.
        & flutter build $Target --release `
            '--dart-define=APP_ENV=prod' `
            '--dart-define=API_BASE_URL=https://hleb-sol.su/Zakaz_http/hs/Obmen/' `
            '--dart-define=DATA_BASE_URL=https://obedmoscow.ru/data/' `
            '--dart-define=APP_VERSION_URL=https://obedmoscow.ru/version.json'
        if ($LASTEXITCODE -ne 0) { throw "Сборка $Target завершилась с ошибкой." }
    }
    finally {
        foreach ($name in @('POLEVAYA_KEYSTORE_PATH','POLEVAYA_KEYSTORE_PASSWORD','POLEVAYA_KEY_ALIAS','POLEVAYA_KEY_PASSWORD')) {
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
    }
}

Push-Location $repoRoot
try {
    Invoke-SignedBuild 'upload' $uploadFile 'appbundle'
    Invoke-SignedBuild 'app-signing' $appFile 'apk'
    Write-Output 'AAB и APK созданы; проверьте package ID, версии и сертификаты перед использованием.'
}
finally { Pop-Location }
