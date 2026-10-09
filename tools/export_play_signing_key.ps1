param(
    [Parameter(Mandatory = $true)][string]$ToolsDir,
    [string]$KeysDir = (Join-Path $env:USERPROFILE 'PolevayaKuhnyaKeys')
)

# Run in an interactive PowerShell terminal. PEPK requests passwords itself.
# No passwords in arguments, environment variables, logs or the repository.
$ErrorActionPreference = 'Stop'
$toolFile = Join-Path $ToolsDir 'pepk.jar'
if (-not (Test-Path -LiteralPath $toolFile -PathType Leaf)) {
    $toolFile = Join-Path $ToolsDir 'pepk'
}
$encryptionFile = Join-Path $ToolsDir 'encryption_public_key.pem'
$keystoreFile = Join-Path $KeysDir 'app-signing.p12'
$outputFile = Join-Path $KeysDir 'play-signing-export.zip'
foreach ($path in @($toolFile, $encryptionFile, $keystoreFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $path" }
}
if (Test-Path -LiteralPath $outputFile) { throw "Export already exists; inspect it before repeating: $outputFile" }
if ([IO.File]::ReadAllText($encryptionFile) -notmatch '-----BEGIN PUBLIC KEY-----') {
    throw 'Expected the encryption public key downloaded from this app in Play Console.'
}
Write-Output 'Use the existing app-signing password at the keystore and key prompts.'
& java -jar $toolFile "--keystore=$keystoreFile" '--alias=app-signing' `
    "--output=$outputFile" '--include-cert' '--rsa-aes-encryption' `
    "--encryption-key-path=$encryptionFile"
if ($LASTEXITCODE -ne 0) { throw 'PEPK export failed. Do not upload an incomplete ZIP.' }
if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf)) { throw 'PEPK did not create the export.' }

$expectedFingerprint = 'CF38A81B902DD55A97B66C2BBD404C644F77628CB4F05A3E71858A09B011458D'
$zip = [IO.Compression.ZipFile]::OpenRead($outputFile)
try {
    if ($zip.Entries.Count -lt 2) { throw 'Expected an encrypted key and certificate in the ZIP.' }
    $matchedCertificate = $false
    foreach ($entry in $zip.Entries) {
        if ($entry.Length -gt 65536) { continue }
        $stream = $entry.Open()
        $buffer = [IO.MemoryStream]::new()
        try { $stream.CopyTo($buffer); $bytes = $buffer.ToArray() }
        finally { $stream.Dispose(); $buffer.Dispose() }
        $certificate = $null
        try {
            $content = [Text.Encoding]::ASCII.GetString($bytes)
            if ($content.Contains('-----BEGIN CERTIFICATE-----')) {
                $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($content)
            } else {
                $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
            }
            if ($certificate.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256) -eq $expectedFingerprint) {
                $matchedCertificate = $true
            }
        } catch { }
        finally { if ($certificate) { $certificate.Dispose() } }
    }
    if (-not $matchedCertificate) { throw 'Export certificate does not match the agreed app-signing certificate. Do not upload.' }
}
finally { $zip.Dispose() }
Write-Output "Verified encrypted export: $outputFile"
Write-Output 'No upload or change to Play Console was performed.'
