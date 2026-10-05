"""Read Google Play metadata for the accepted build; never create an edit/release."""

import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


PACKAGE = "ru.obedmoscow.polevayakuhnya"
VERSION_CODE = 71  # Existing accepted bundle; independent of the next source version.
PROJECT = "api-4947197285670194433-706630"
ACCOUNT = f"codemagic-polevaya-kuhnya@{PROJECT}.iam.gserviceaccount.com"
CERTIFICATE = "cf38a81b902dd55a97b66c2bbd404c644f77628cb4f05a3e71858a09b011458d"
TOKEN_URL = "https://oauth2.googleapis.com/token"
REPORT = Path("build/release-check/google-play-access.json")


class CheckFailure(Exception):
    pass


def encoded(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def request_json(request, step):
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        reasons = {
            400: "Invalid request or credential; check JSON and machine clock.",
            401: "Authentication rejected; check active service account key.",
            403: "Access denied; check enabled API and app-scoped Play permissions.",
            404: "Package or accepted build 71 not found for this account.",
            429: "Google request quota exceeded; retry later.",
        }
        # Never print Google's raw body, request headers, JWT, or credentials.
        raise CheckFailure(f"{step}: HTTP {error.code}. " + reasons.get(
            error.code, "Google request failed; retry later.")) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise CheckFailure(f"{step}: network/HTTPS request failed.") from None
    except (ValueError, TypeError):
        raise CheckFailure(f"{step}: invalid JSON response.") from None


def access_token():
    raw = os.environ.pop("GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS", "")
    if not raw:
        raise CheckFailure("Missing GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS; check group google_play_release.")
    try:
        credential = json.loads(raw)
    except ValueError:
        raise CheckFailure("Secret must contain complete JSON, not base64 or a file path.") from None
    if not isinstance(credential, dict) or any((
        credential.get("type") != "service_account",
        credential.get("project_id") != PROJECT,
        credential.get("client_email") != ACCOUNT,
        credential.get("token_uri") != TOKEN_URL,
    )):
        raise CheckFailure("Secret belongs to an unexpected service account/project or token endpoint.")
    private_key = credential.get("private_key", "")
    if not isinstance(private_key, str) or not private_key.startswith("-----BEGIN PRIVATE KEY-----"):
        raise CheckFailure("Secret private key has an invalid PEM format.")
    now = int(time.time())
    header = encoded(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = encoded(json.dumps({
        "iss": ACCOUNT,
        "scope": "https://www.googleapis.com/auth/androidpublisher",
        "aud": TOKEN_URL,
        "iat": now,
        "exp": now + 600,
    }).encode())
    unsigned = header + b"." + claims
    with tempfile.TemporaryDirectory(prefix="play-api-key-") as directory:
        key_path = Path(directory) / "key.pem"
        # Create with owner-only permissions before writing private content.
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as key_file:
            key_file.write(private_key)
        try:
            signature = subprocess.run(
                ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
                input=unsigned, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                check=True, timeout=20,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            raise CheckFailure("Cannot sign authentication assertion; check OpenSSL and private key.") from None
    assertion = (unsigned + b"." + encoded(signature)).decode()
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion,
    }).encode()
    result = request_json(urllib.request.Request(TOKEN_URL, data=body, method="POST"), "Authentication")
    token = result.get("access_token") if isinstance(result, dict) else None
    if not isinstance(token, str) or not token:
        raise CheckFailure("Authentication response contains no access token.")
    return token


def normalize_certificate(value):
    if not isinstance(value, str):
        return ""
    compact = value.replace(":", "").lower()
    if len(compact) == 64 and all(char in "0123456789abcdef" for char in compact):
        return compact
    try:
        return base64.b64decode(value, validate=True).hex()
    except ValueError:
        return ""


def main():
    report = {"package": PACKAGE, "versionCode": VERSION_CODE,
              "releaseModified": False, "status": "failed"}
    try:
        token = access_token()
        url = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}/generatedApks/{VERSION_CODE}"
        result = request_json(urllib.request.Request(
            url, headers={"Authorization": f"Bearer {token}"}, method="GET"), "Read generated APK metadata")
        groups = result.get("generatedApks", []) if isinstance(result, dict) else []
        hashes = sorted({normalize_certificate(group.get("certificateSha256Hash"))
                         for group in groups if isinstance(group, dict)} - {""})
        if CERTIFICATE not in hashes:
            raise CheckFailure("Google metadata does not contain the expected app-signing certificate.")
        report.update(status="passed", certificateSha256=hashes)
        print("Google Play API access verified for existing build 71; signing certificate matches. No release modified.")
    except CheckFailure as error:
        report["reason"] = str(error)
        print(f"Google Play API check failed: {error}")
    except Exception:
        # Suppress tracebacks that could contain sensitive request context.
        report["reason"] = "Unexpected check failure; no credential details logged."
        print(report["reason"])
    finally:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
