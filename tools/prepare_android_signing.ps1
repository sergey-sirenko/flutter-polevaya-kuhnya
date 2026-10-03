param(
    [string]$PrimaryDir = (Join-Path $env:USERPROFILE 'PolevayaKuhnyaKeys'),
    [string]$BackupDir = 'E:\Backups\PolevayaKuhnya'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$primaryFull = [IO.Path]::GetFullPath($PrimaryDir)
$backupFull = [IO.Path]::GetFullPath($BackupDir)

function Test-InDirectory([string]$Candidate, [string]$Directory) {
    $root = $Directory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $Candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
}

if ((Test-InDirectory $primaryFull $repoRoot) -or (Test-InDirectory $backupFull $repoRoot)) {
    throw 'Keystore и резерв должны находиться вне репозитория.'
}
if ($primaryFull -eq $backupFull) { throw 'Рабочая и резервная папки должны различаться.' }
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) { throw 'keytool не найден в PATH.' }

function Read-PasswordTwice([string]$Label) {
    $first = Read-Host "Пароль $Label (не показывается)" -AsSecureString
    $second = Read-Host "Повторите пароль $Label" -AsSecureString
    $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
    $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
    try {
        $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
        $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
        if ($plain1.Length -lt 16) { throw 'Пароль должен содержать не менее 16 символов.' }
        if ($plain1 -cne $plain2) { throw 'Пароли не совпадают.' }
        return $plain1
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
    }
}

New-Item -ItemType Directory -Path $primaryFull -Force | Out-Null
New-Item -ItemType Directory -Path $backupFull -Force | Out-Null

try {
    foreach ($spec in @(
        @{ Name = 'app-signing.p12'; Alias = 'app-signing'; Env = 'PK_APP_SIGNING_PASSWORD' },
        @{ Name = 'upload.p12'; Alias = 'upload'; Env = 'PK_UPLOAD_PASSWORD' }
    )) {
        $password = Read-PasswordTwice $spec.Alias
        [Environment]::SetEnvironmentVariable($spec.Env, $password, 'Process')
        $password = $null
        $source = Join-Path $primaryFull $spec.Name
        $copy = Join-Path $backupFull $spec.Name
        $sourceExists = Test-Path -LiteralPath $source
        $copyExists = Test-Path -LiteralPath $copy
        if ($sourceExists -ne $copyExists) {
            throw "Для $($spec.Name) существует только одна копия. Проверьте вручную; перезаписи нет."
        }
        if (-not $sourceExists) {
            & keytool -genkeypair -alias $spec.Alias -keyalg RSA -keysize 4096 `
                -validity 10000 -dname 'CN=Polevaya Kuhnya' -storetype PKCS12 `
                -keystore $source -storepass:env $spec.Env -keypass:env $spec.Env -noprompt
            if ($LASTEXITCODE -ne 0) { throw "Не удалось создать $($spec.Name)." }
            Copy-Item -LiteralPath $source -Destination $copy -ErrorAction Stop
        }
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $copyHash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
        if ($sourceHash -ne $copyHash) { throw "Резерв $($spec.Name) не совпадает с оригиналом." }
        & keytool -list -keystore $copy -storetype PKCS12 -alias $spec.Alias -storepass:env $spec.Env | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Резерв $($spec.Name) не открылся." }
        $certPath = Join-Path $primaryFull ($spec.Alias + '-certificate.pem')
        & keytool -exportcert -rfc -alias $spec.Alias -keystore $source -storetype PKCS12 `
            -storepass:env $spec.Env -file $certPath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Не удалось экспортировать сертификат $($spec.Alias)." }
        $pem = Get-Content -LiteralPath $certPath -Raw
        $encoded = ($pem -replace '-----BEGIN CERTIFICATE-----', '' -replace '-----END CERTIFICATE-----', '' -replace '\s', '')
        $der = [Convert]::FromBase64String($encoded)
        $fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($der))
        Write-Output "$($spec.Alias): SHA-256 сертификата $fingerprint"
        Write-Output "SHA-256 файла $($spec.Name): $sourceHash"
        [Environment]::SetEnvironmentVariable($spec.Env, $null, 'Process')
    }
    Write-Output "Рабочая папка: $primaryFull"
    Write-Output "Резервная папка: $backupFull"
    Write-Output 'Сохраните оба пароля в своём менеджере паролей. Они не записаны в файлы и не выводились.'
}
finally {
    [Environment]::SetEnvironmentVariable('PK_APP_SIGNING_PASSWORD', $null, 'Process')
    [Environment]::SetEnvironmentVariable('PK_UPLOAD_PASSWORD', $null, 'Process')
}
