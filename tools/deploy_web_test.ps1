param(
    [switch]$SkipBuild,
    [string]$SshHost = '185.233.200.63'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = Join-Path $repoRoot 'build/web'
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$runRoot = Join-Path $repoRoot "build/deploy-web-test/$stamp"
$remoteArchive = "/var/tmp/flutter-web-$stamp.tar.gz"
$remoteManifest = "/var/tmp/flutter-web-$stamp.json"
$remoteScript = "/var/tmp/flutter-web-$stamp.sh"
$manifestLocal = Join-Path $runRoot "flutter-web-$stamp.json"
$archiveLocal = Join-Path $runRoot "flutter-web-$stamp.tar.gz"
$remoteScriptLocal = Join-Path $runRoot "flutter-web-$stamp.sh"

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        & (Join-Path $PSScriptRoot 'build_web_test.ps1')
        if (-not $?) { throw 'Web test build failed.' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $buildRoot 'index.html'))) {
        throw 'build/web is missing. Run without -SkipBuild to create it.'
    }

    $versionPath = Join-Path $buildRoot 'version.json'
    $versionRaw = [IO.File]::ReadAllText($versionPath)
    & python (Join-Path $PSScriptRoot 'check_web_version_policy.py') `
        --version $versionPath `
        --pubspec (Join-Path $repoRoot 'pubspec.yaml')
    if ($LASTEXITCODE -ne 0) { throw 'build/web/version.json failed the test policy check.' }
    $version = $versionRaw | ConvertFrom-Json
    if (-not $version.version -or ($version.build -isnot [int] -and $version.build -isnot [long]) -or $version.build -lt 1) {
        throw 'build/web/version.json has an invalid version or build number.'
    }
    $files = @(Get-ChildItem -LiteralPath $buildRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path = [IO.Path]::GetRelativePath($buildRoot, $_.FullName).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            size = $_.Length
        }
    })
    $manifest = [ordered]@{
        version = $version.version
        build = $version.build
        versionJson = $versionRaw.Trim()
        files = $files
    }
    [IO.File]::WriteAllText($manifestLocal, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    tar -czf $archiveLocal -C $buildRoot .
    if ($LASTEXITCODE -ne 0) { throw 'Could not archive build/web.' }
    $archiveHash = (Get-FileHash -LiteralPath $archiveLocal -Algorithm SHA256).Hash.ToLowerInvariant()

    $remoteBody = @'
#!/bin/sh
set -eu
archive='@@ARCHIVE@@'
manifest='@@MANIFEST@@'
active=/var/www/flutter-test
stage=/var/www/.flutter-test-stage-@@STAMP@@
backup=/var/backups/flutter/WEBTEST-@@STAMP@@
test -d "$active"
test ! -e "$stage"
test ! -e "$backup"
test "$(stat -c %d /var/www)" = "$(stat -c %d /var/backups)"
systemctl is-active --quiet caddy
printf '%s  %s\n' '@@ARCHIVE_HASH@@' "$archive" | sha256sum -c -
mkdir -p /var/backups/flutter
mkdir -m 700 "$backup"
cp "$manifest" "$backup/release-files.json"
sha256sum /etc/caddy/Caddyfile > "$backup/caddy-before.sha256"
tar -czf "$backup/web-before.tar.gz" -C "$active" .
chmod 600 "$backup/web-before.tar.gz"
python3 - "$active/version.json" "$manifest" <<'PY'
import json,pathlib,sys
old=json.loads(pathlib.Path(sys.argv[1]).read_text())
new=json.loads(pathlib.Path(sys.argv[2]).read_text())
rank=lambda v: tuple(int(x) for x in v.split('.'))
if (rank(old['version']),int(old['build'])) >= (rank(new['version']),int(new['build'])):
 raise SystemExit(f"Refusing non-forward deploy: {old} -> {new}")
PY
mkdir -m 755 "$stage"
tar -xzf "$archive" -C "$stage"
python3 - "$stage" "$manifest" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);m=json.loads(pathlib.Path(sys.argv[2]).read_text())
assert json.loads((root/'version.json').read_text())==json.loads(m['versionJson'])
assert (json.loads(m['versionJson'])['version'],int(json.loads(m['versionJson'])['build']))==(m['version'],int(m['build']))
expected={f['path'] for f in m['files']}
actual={str(p.relative_to(root)).replace('\\','/') for p in root.rglob('*') if p.is_file()}
assert actual==expected,(actual-expected,expected-actual)
for f in m['files']:
 p=root/f['path']
 assert p.stat().st_size==f['size'],f['path']
 assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256'],f['path']
print('Staging hashes OK:',len(expected),'files')
PY
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
rollback() {
 if test -d "$backup/web-before-directory"; then
   if test -d "$active"; then mv "$active" "$backup/web-failed-directory"; fi
   mv "$backup/web-before-directory" "$active"
 fi
}
trap rollback HUP INT TERM EXIT
mv "$active" "$backup/web-before-directory"
mv "$stage" "$active"
python3 - "$active" "$manifest" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);m=json.loads(pathlib.Path(sys.argv[2]).read_text())
for f in m['files']:
 assert hashlib.sha256((root/f['path']).read_bytes()).hexdigest()==f['sha256'],f['path']
print('Active hashes OK:',len(m['files']),'files')
PY
sha256sum -c "$backup/caddy-before.sha256"
remote_version=$(curl -fsS https://flutter-test.obedmoscow.ru/version.json)
python3 -c 'import json,sys; a=json.loads(sys.argv[1]); m=json.load(open(sys.argv[2])); b=json.loads(m["versionJson"]); assert a==b and (a["version"],int(a["build"]))==(m["version"],int(m["build"])), (a,b); print("Public version OK:",a["version"],a["build"])' "$remote_version" "$manifest"
systemctl is-active caddy
cat > "$backup/rollback.sh" <<'ROLLBACK'
#!/bin/sh
set -eu
backup=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
active=/var/www/flutter-test
old="$backup/web-before-directory"
failed="$backup/web-after-rollback"
test -d "$active"
test -d "$old"
test ! -e "$failed"
before=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d["version"])+"+"+str(d["build"]))' "$old/version.json")
mv "$active" "$failed"
if ! mv "$old" "$active"; then mv "$failed" "$active"; exit 1; fi
actual=$(curl -fsS https://flutter-test.obedmoscow.ru/version.json)
if ! python3 -c 'import json,sys; a=json.loads(sys.argv[1]); b=json.load(open(sys.argv[2])); assert a==b' "$actual" "$active/version.json"; then
 mv "$active" "$backup/web-rollback-failed-directory"
 mv "$failed" "$active"
 exit 1
fi
systemctl is-active caddy
printf 'Restored %s; newer build kept in %s\n' "$before" "$failed"
ROLLBACK
chmod 700 "$backup/rollback.sh"
trap - HUP INT TERM EXIT
mv "$archive" "$backup/web-new.tar.gz"
mv "$manifest" "$backup/release-files.json"
printf 'Backup: %s\n' "$backup"
'@
    $remoteBody = $remoteBody.Replace('@@ARCHIVE@@', $remoteArchive).Replace('@@MANIFEST@@', $remoteManifest)
    $remoteBody = $remoteBody.Replace('@@STAMP@@', $stamp).Replace('@@ARCHIVE_HASH@@', $archiveHash)
    [IO.File]::WriteAllText($remoteScriptLocal, $remoteBody.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))

    $preflightCommand = @'
set -eu
test -d /var/www/flutter-test
test -d /var/backups
test ! -e '@@ARCHIVE@@'
test ! -e '@@MANIFEST@@'
test ! -e '@@SCRIPT@@'
python3 -c 'import json; d=json.load(open("/var/www/flutter-test/version.json")); print(str(d["version"])+"+"+str(d["build"]))'
systemctl is-active caddy
'@
    $preflightCommand = $preflightCommand.Replace('@@ARCHIVE@@', $remoteArchive).Replace('@@MANIFEST@@', $remoteManifest).Replace('@@SCRIPT@@', $remoteScript).Replace("`r`n", "`n")
    $preflight = & ssh -o BatchMode=yes -o ConnectTimeout=20 $SshHost $preflightCommand
    if ($LASTEXITCODE -ne 0) { throw 'SSH preflight failed; no remote files were changed.' }
    Write-Output "Current remote version: $($preflight[0])"

    & scp -o BatchMode=yes -o ConnectTimeout=20 $archiveLocal $manifestLocal $remoteScriptLocal "${SshHost}:/var/tmp/"
    if ($LASTEXITCODE -ne 0) { throw 'Could not transfer the build package.' }
    & ssh -o BatchMode=yes -o ConnectTimeout=20 $SshHost "sh '$remoteScript'"
    if ($LASTEXITCODE -ne 0) { throw 'Remote deployment failed; inspect the reported backup path before retrying.' }

    $publicPath = Join-Path $runRoot 'public-version.json'
    [IO.File]::WriteAllText($publicPath, (Invoke-WebRequest -UseBasicParsing 'https://flutter-test.obedmoscow.ru/version.json').Content, [Text.UTF8Encoding]::new($false))
    $expectedPath = Join-Path $runRoot 'expected-version.json'
    [IO.File]::WriteAllText($expectedPath, $versionRaw.Trim(), [Text.UTF8Encoding]::new($false))
    & python -c 'import json,pathlib,sys; public=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")); expected=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")); assert public==expected, (public, expected); print("Published", str(public["version"])+"+"+str(public["build"]))' $publicPath $expectedPath
    if ($LASTEXITCODE -ne 0) { throw 'The public version.json does not match the uploaded build.' }
    Write-Output "Archive SHA-256: $archiveHash"
    Write-Output "Local record: $runRoot"
}
finally { Pop-Location }
