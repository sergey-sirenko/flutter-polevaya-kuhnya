"""Upload one reviewed, existing IPA; no rebuild, beta review or distribution."""
from datetime import datetime, timezone
import argparse
from importlib.metadata import version as package_version
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

from prepare_android_ci import PreparationError, require, run
from prepare_ios_ci import decode_profile, verify_ipa, CERT_SHA1

MANIFEST = Path("docs/releases/ios-1.0.0-71.json")
OUTPUT = Path("build/release/ios-upload")
API = "https://api.appstoreconnect.apple.com"


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def jwt(key, issuer, key_id):
    header = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    body = b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 300,
                          "aud": "appstoreconnect-v1"}).encode())
    message = f"{header}.{body}"
    signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key)],
                            input=message.encode(), stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, timeout=30)
    require(signed.returncode == 0, "Cannot sign Apple API token.")
    # P-256 signatures fit in a short ASN.1 DER sequence of two INTEGERs.
    der = signed.stdout
    require(len(der) >= 8 and der[0] == 0x30 and der[1] == len(der) - 2, "Unexpected ES256 signature.")
    position = 2
    values = []
    for _ in range(2):
        require(der[position] == 2, "Invalid ES256 INTEGER.")
        length = der[position + 1]
        value = int.from_bytes(der[position + 2:position + 2 + length], "big")
        values.append(value.to_bytes(32, "big"))
        position += 2 + length
    require(position == len(der), "Unexpected signature bytes.")
    return message + "." + b64(b"".join(values))


def get(url, key, issuer, key_id):
    require(url.startswith(API + "/v1/"), "Refusing unknown API destination.")
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + jwt(key, issuer, key_id)})
    # API tokens must not follow redirects to another host.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    with urllib.request.build_opener(NoRedirect).open(request, timeout=40) as response:
        return json.load(response)


def existing(manifest, key, issuer, key_id):
    query = urllib.parse.urlencode({"filter[app]": manifest["appId"],
                                   "filter[version]": manifest["buildNumber"],
                                   "include": "preReleaseVersion", "limit": 200})
    result = get(API + "/v1/builds?" + query, key, issuer, key_id)
    require(not result.get("links", {}).get("next"), "Too many matching builds; inspect manually.")
    versions = {item["id"]: item["attributes"] for item in result.get("included", [])
                if item["type"] == "preReleaseVersions"}
    matches = []
    for item in result["data"]:
        reference = item["relationships"]["preReleaseVersion"]["data"]["id"]
        require(reference in versions, "Apple did not return pre-release version.")
        release = versions[reference]
        if release.get("platform") == "IOS" and release["version"] == manifest["version"]:
            matches.append(item)
    require(len(matches) <= 1, "Ambiguous existing build; inspect manually.")
    return matches[0] if matches else None


def record_build(report, build):
    report.update(buildId=build["id"], processingState=build["attributes"].get("processingState"),
                  expired=build["attributes"].get("expired"), status="existing_build")
    require(not report["expired"] and report["processingState"] not in ("FAILED", "INVALID"),
            "Existing build is expired or invalid; do not reupload the same number.")


def perform(report, action):
    require(sys.platform == "darwin" and os.environ.get("CM_BUILD_ID"), "Run only on Codemagic macOS.")
    require(action in ("status", "upload"), "Unknown action.")
    manifest = json.loads(MANIFEST.read_text())
    report["workflowCommit"] = run(["git", "rev-parse", "HEAD"]).strip()
    require(not run(["git", "status", "--porcelain", "--untracked-files=no"]).strip(),
            "Workflow checkout has tracked changes.")
    from prepare_ios_ci import version
    require(version() == (manifest["version"], manifest["buildNumber"]),
            "Manifest version differs from pubspec; review the next release separately.")
    report.update(action=action, sourceCommit=manifest["sourceCommit"], sourceBuildId=manifest["sourceBuildId"],
                  version=manifest["version"], buildNumber=manifest["buildNumber"], sha256=manifest["sha256"])
    names = ("APP_STORE_CONNECT_PRIVATE_KEY", "APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_ISSUER_ID")
    require(all(os.environ.get(n) for n in names), "Missing Apple API Secret.")
    issuer, key_id = os.environ[names[2]], os.environ[names[1]]
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("APP_STORE_CONNECT_", "IOS_", "ANDROID_", "GOOGLE_PLAY_"))}
    cli = run(["app-store-connect", "--version"], env).strip()
    report["codemagicCli"] = cli
    installed_version = package_version("codemagic-cli-tools")
    report["codemagicCliPackageVersion"] = installed_version
    require(installed_version == "0.69.0" and "0.69.0" in cli,
            "Expected Codemagic CLI 0.69.0; review tool upgrade explicitly.")
    with tempfile.TemporaryDirectory(prefix="polevaya-upload-") as tmp:
        directory = Path(tmp)
        key = directory / "api.p8"
        with os.fdopen(os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
            stream.write(os.environ[names[0]])
        app = get(API + "/v1/apps/" + manifest["appId"], key, issuer, key_id)
        require(app["data"]["attributes"]["bundleId"] == manifest["bundleId"], "Wrong Apple app.")
        build = existing(manifest, key, issuer, key_id)
        report["storeVersionAvailabilityChecked"] = True
        if build:
            record_build(report, build)
            return
        if action == "status":
            report["status"] = "not_found"
            return
        report["step"] = "artifact_verification"
        url = manifest["artifactUrl"]
        parsed = urllib.parse.urlsplit(url)
        require(parsed.scheme == "https" and parsed.netloc == "api.codemagic.io"
                and parsed.path.startswith("/artifacts/") and not parsed.query,
                "Expected reviewed Codemagic artifact URL.")
        ipa = directory / "app.ipa"
        # No Apple credentials are used for downloading the artifact.
        with urllib.request.urlopen(url, timeout=60) as response, ipa.open("wb") as stream:
            total = 0
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                require(total <= 500 * 1024 * 1024, "IPA exceeds download size limit.")
                stream.write(chunk)
        require(hashlib.sha256(ipa.read_bytes()).hexdigest() == manifest["sha256"], "Downloaded IPA hash mismatch.")
        with zipfile.ZipFile(ipa) as archive:
            entries = [n for n in archive.namelist() if n.startswith("Payload/")
                       and n.count("/") == 2 and n.endswith(".app/embedded.mobileprovision")]
            require(len(entries) == 1, "Expected one embedded App Store profile.")
            profile_path = directory / "profile.mobileprovision"
            profile_path.write_bytes(archive.read(entries[0]))
        profile = decode_profile(profile_path, env)
        require(manifest["certificateSha1"] == CERT_SHA1, "Manifest signer differs from accepted signer.")
        verify_ipa(ipa, directory, profile, manifest["version"], manifest["buildNumber"], env)
        # Recheck immediately before submission. Never delete/cancel any existing build.
        build = existing(manifest, key, issuer, key_id)
        if build:
            record_build(report, build)
            return
        report.update(step="upload", status="upload_unknown", uploadAttempted=True)
        run(["app-store-connect", "publish", "--path", str(ipa), "--issuer-id", issuer,
             "--key-id", key_id, "--private-key", "@file:" + str(key),
             "--enable-package-validation", "--altool-retries", "1"], env)
        report.update(status="uploaded", storeUploadPerformed=True, step="complete")
        # No beta review, groups, testers or App Review flags: only binary upload.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", required=True, choices=("status", "upload"))
    action = parser.parse_args().action
    report = {"status": "failed", "step": "preflight", "appId": "6819387151",
              "storeUploadPerformed": False, "uploadAttempted": False,
              "storeVersionAvailabilityChecked": False, "reviewSubmitted": False,
              "testerDistributionRequested": False, "startedAtUtc": datetime.now(timezone.utc).isoformat()}
    try:
        perform(report, action)
    except Exception as error:
        report["reason"] = str(error) if isinstance(error, PreparationError) else f"Stopped ({type(error).__name__}); diagnostics suppressed."
        if not report["uploadAttempted"]:
            report["status"] = "failed"
    finally:
        report["finishedAtUtc"] = datetime.now(timezone.utc).isoformat()
        OUTPUT.mkdir(parents=True, exist_ok=True)
        (OUTPUT / "upload-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("Apple upload/status result: " + report["status"])
    return 1 if report["status"] in ("failed", "upload_unknown") or report.get("reason") else 0


if __name__ == "__main__":
    raise SystemExit(main())
