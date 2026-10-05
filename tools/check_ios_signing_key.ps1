param(
    [string]$P12Path = 'C:\Users\Sergey\PolevayaKuhnyaKeys\iOS\ХлебСольМоб_IOS\developer_identity.p12',
    [string]$CertificatePath = 'C:\Users\Sergey\PolevayaKuhnyaKeys\iOS\ХлебСольМоб_IOS\Сертификат ios разработчика\ios_distribution.cer'
)
$ErrorActionPreference = 'Stop'
$password = Read-Host 'Enter existing P12 password (local check only)' -AsSecureString
$certificates = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
$expected = $null
$passwordPointer = [IntPtr]::Zero
$plainPassword = $null
$stage = 'certificate-file'
try {
    $expected = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
    $stage = 'p12-import'
    # Collection.Import accepts String, not SecureString, in PowerShell 7/.NET.
    # Convert only in memory; never write the password to output or a file.
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $certificates.Import($P12Path, $plainPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
    $plainPassword = $null
    $stage = 'certificate-match'
    Write-Host 'P12 OPENED. Public certificate details (no private-key data):'
    foreach ($item in $certificates) {
        Write-Host ('Subject: ' + $item.Subject)
        Write-Host ('Certificate SHA1: ' + $item.Thumbprint)
        Write-Host ('Has private key: ' + $item.HasPrivateKey)
        Write-Host ('Valid until UTC: ' + $item.NotAfter.ToUniversalTime().ToString('u'))
    }
    Write-Host ('Expected distribution SHA1: ' + $expected.Thumbprint)
    $matching = @($certificates | Where-Object { $_.Thumbprint -eq $expected.Thumbprint -and $_.HasPrivateKey })
    if ($matching.Count -ne 1) { throw 'No matching distribution certificate with a private key.' }
    $stage = 'certificate-expiry'
    if ($expected.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow) { throw 'Distribution certificate has expired.' }
    Write-Host 'VERIFIED: P12 contains the private key for the distribution certificate.'
    Write-Host ('Certificate SHA1: ' + $expected.Thumbprint)
    Write-Host ('Valid until UTC: ' + $expected.NotAfter.ToUniversalTime().ToString('u'))
    Write-Host 'No key was saved, uploaded or installed. No build was started.'
} catch {
    # Do not echo raw exceptions: show only a fixed, non-sensitive diagnostic.
    switch ($stage) {
        'certificate-file' { Write-Host 'NOT VERIFIED: cannot read the public certificate file.' }
        'p12-import' { Write-Host 'NOT VERIFIED: cannot open P12; check its path, password and file format.' }
        'certificate-match' { Write-Host 'NOT VERIFIED: P12 opened, but no matching distribution private key was found.' }
        'certificate-expiry' { Write-Host 'NOT VERIFIED: distribution certificate has expired.' }
    }
    exit 1
} finally {
    $plainPassword = $null
    if ($passwordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
    foreach ($certificate in $certificates) { $certificate.Dispose() }
    if ($null -ne $expected) { $expected.Dispose() }
    $password.Dispose()
}
