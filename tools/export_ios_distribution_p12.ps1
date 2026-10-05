param([string]$SigningDir = 'C:\Users\Sergey\PolevayaKuhnyaKeys\iOS\PolevayaKuhnyaDistribution20261005')
$ErrorActionPreference = 'Stop'
$outputPath = Join-Path $SigningDir 'distribution.p12'
if (Test-Path -LiteralPath $outputPath) { throw 'distribution.p12 already exists; no overwrite performed.' }
$password = Read-Host 'Choose a new P12 password' -AsSecureString
$confirmation = Read-Host 'Repeat the new P12 password' -AsSecureString
$pointer = [IntPtr]::Zero
$confirmationPointer = [IntPtr]::Zero
$plain = $null
$repeat = $null
$certificate = $null
$identity = $null
$rsa = [Security.Cryptography.RSA]::Create()
$verification = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $confirmationPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmation)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    $repeat = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmationPointer)
    if ([string]::IsNullOrEmpty($plain) -or $plain -cne $repeat) { throw 'Password confirmation failed.' }
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $SigningDir 'distribution.cer'))
    if ($certificate.Thumbprint -ne '0556DF536EE5F42D407B48B6029FCE1FD1ED5E37') { throw 'Unexpected certificate.' }
    $rsa.ImportFromPem([IO.File]::ReadAllText((Join-Path $SigningDir 'distribution-private-key.pem')))
    $identity = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($certificate, $rsa)
    $bytes = $identity.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $plain)
    $verification.Import($bytes, $plain, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
    if (@($verification | Where-Object { $_.HasPrivateKey -and $_.Thumbprint -eq $certificate.Thumbprint }).Count -ne 1) { throw 'P12 verification failed.' }
    $stream = [IO.File]::Open($outputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    Write-Host ('VERIFIED P12 saved: ' + $outputPath)
    Write-Host ('Certificate SHA1: ' + $certificate.Thumbprint)
    Write-Host 'No upload or iOS build was performed. Keep the P12 password in your password manager.'
} catch {
    Write-Host 'NOT EXPORTED: check password confirmation and local certificate/key files. No existing P12 was overwritten.'
    exit 1
} finally {
    $plain = $null; $repeat = $null; $bytes = $null
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    if ($confirmationPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationPointer) }
    foreach ($item in $verification) { $item.Dispose() }
    if ($null -ne $identity) { $identity.Dispose() }
    if ($null -ne $certificate) { $certificate.Dispose() }
    $rsa.Dispose(); $password.Dispose(); $confirmation.Dispose()
}
