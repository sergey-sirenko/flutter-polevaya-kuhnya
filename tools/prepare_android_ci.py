"""Codemagic preparation only. No store credentials, edits, uploads or version changes."""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

PACKAGE = "ru.obedmoscow.polevayakuhnya"
CERTS = {
    "google_play": "4119b022eade3b347750120c69dae323372f4cd42c7e75fce4ce82de5d1d1fe9",
    "rustore": "cf38a81b902dd55a97b66c2bbd404c644f77628cb4f05a3e71858a09b011458d",
}
API = "https://hleb-sol.su/Zakaz_http/hs/Obmen/"
DATA = "https://obedmoscow.ru/data/"
VERSION_URL = "https://obedmoscow.ru/version.json"
BUNDLE_URL = "https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar"
BUNDLE_HASH = "fb05065f66c1d56e6f1d543399e8334d275f65659def98c79426bf94f1bc136c"
OUTPUT = Path("build/release/android")


class PreparationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise PreparationError(message)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def run(args, env=None):
    # Do not expose Gradle diagnostics or process environment containing passwords.
    result = subprocess.run(args, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=2400)
    require(result.returncode == 0, f"Command failed: {Path(args[0]).name} {args[1] if len(args) > 1 else ''}; exit {result.returncode}.")
    return result.stdout.decode("utf-8", errors="replace")


def get_json(url):
    with urllib.request.urlopen(url, timeout=40) as response:
        require(response.status == 200 and response.url == url,
                f"Unexpected response or redirect: {url}")
        return json.load(response)


def identity():
    matches = re.findall(r"^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$",
                         Path("pubspec.yaml").read_text(), re.M)
    require(len(matches) == 1, "pubspec.yaml must have one version: X.Y.Z+N.")
    version, build = matches[0]
    require(int(build) <= 2100000000, "Android versionCode exceeds store limit.")
    return version, int(build)


def signing_env(store, directory):
    prefix, alias = ("UPLOAD", "upload") if store == "google_play" else ("APP_SIGNING", "app-signing")
    names = [f"ANDROID_{prefix}_{suffix}" for suffix in
             ("KEYSTORE_BASE64", "STORE_PASSWORD", "KEY_PASSWORD")]
    require(all(os.environ.get(name) for name in names),
            f"Missing signing secret for {store}: " + ", ".join(names))
    try:
        data = base64.b64decode(os.environ[names[0]], validate=True)
    except ValueError:
        raise PreparationError(f"ANDROID_{prefix}_KEYSTORE_BASE64 is not valid base64.") from None
    path = directory / f"{alias}.p12"
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
        stream.write(data)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("ANDROID_UPLOAD_") and not key.startswith("ANDROID_APP_SIGNING_")
           and key != "GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS"}
    env.update(POLEVAYA_KEYSTORE_PATH=str(path), POLEVAYA_KEY_ALIAS=alias,
               POLEVAYA_KEYSTORE_PASSWORD=os.environ[names[1]],
               POLEVAYA_KEY_PASSWORD=os.environ[names[2]], LC_ALL="en_US.UTF-8")
    # Check certificate first, then validate key password with a private-key operation.
    cert = subprocess.run(["keytool", "-exportcert", "-keystore", str(path), "-storetype", "PKCS12",
                           "-alias", alias, "-storepass:env", "POLEVAYA_KEYSTORE_PASSWORD"],
                          env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    require(cert.returncode == 0, f"Cannot open {alias} keystore or alias.")
    require(hashlib.sha256(cert.stdout).hexdigest() == CERTS[store], f"Wrong {alias} certificate.")
    request = directory / f"{alias}.csr"
    run(["keytool", "-certreq", "-keystore", str(path), "-alias", alias,
         "-storepass:env", "POLEVAYA_KEYSTORE_PASSWORD", "-keypass:env", "POLEVAYA_KEY_PASSWORD",
         "-file", str(request)], env)
    return env


def verify(store, artifact, version, build, sdk_tools, bundle):
    if store == "google_play":
        run(["java", "tools/VerifyBundle.java", str(artifact), CERTS[store]])
        run(["java", "-jar", str(bundle), "validate", f"--bundle={artifact}"])
        manifest = ET.fromstring(run(["java", "-jar", str(bundle), "dump", "manifest",
                                      f"--bundle={artifact}", "--module=base"]))
        android = "{http://schemas.android.com/apk/res/android}"
        require(manifest.get("package") == PACKAGE and manifest.get(android + "versionName") == version
                and manifest.get(android + "versionCode") == str(build), "AAB identity mismatch.")
    else:
        signed = run([str(sdk_tools / "apksigner"), "verify", "--verbose", "--print-certs", str(artifact)])
        hashes = re.findall(r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]+)", signed)
        require([value.lower() for value in hashes] == [CERTS[store]], "APK certificate mismatch.")
        manifest = run([str(sdk_tools / "aapt2"), "dump", "badging", str(artifact)])
        match = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", manifest)
        require(match is not None and match.groups() == (PACKAGE, str(build), version), "APK identity mismatch.")


def prepare(report):
    require(os.environ.get("RELEASE_MODE") == "prepare", "Only prepare mode is supported; no store upload.")
    commit = os.environ.get("RELEASE_COMMIT", "")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "RELEASE_COMMIT must be a full lowercase Git SHA.")
    require(run(["git", "rev-parse", "HEAD"]).strip() == commit, "Selected Git commit does not match RELEASE_COMMIT.")
    require(not run(["git", "status", "--porcelain", "--untracked-files=no"]).strip(), "Tracked checkout is not clean.")
    selected = os.environ.get("RELEASE_STORES", "").split(",")
    require(selected in [["google_play"], ["rustore"], ["google_play", "rustore"]], "Invalid Android store selection.")
    notes = os.environ.get("RELEASE_NOTES", "").strip()
    require(notes and len(notes) <= 500, "Release notes must contain 1–500 characters.")
    version, build = identity()
    report.update(commit=commit, version=version, versionCode=build, releaseNotes=notes,
                  channels={store: {"status": "pending"} for store in selected})
    require(not any(OUTPUT.glob("*.aab")) and not any(OUTPUT.glob("*.apk")), "Output already contains artifacts; use a fresh CI checkout.")
    # Validate production policy and menu using public GETs; business API only DNS/TLS.
    policy = get_json(VERSION_URL)
    require(policy.get("policy", {}).get("schema") == 1
            and policy["policy"].get("environment") == "prod", "Production version policy is invalid.")
    require(isinstance(get_json(DATA + "dishes.json"), (dict, list)), "Menu is not JSON object/array.")
    with socket.create_connection(("hleb-sol.su", 443), timeout=20) as connection:
        with ssl.create_default_context().wrap_socket(connection, server_hostname="hleb-sol.su"):
            pass
    flutter = json.loads(run(["flutter", "--version", "--machine"]))
    require(flutter.get("frameworkVersion") == "3.47.1", "Expected Flutter 3.47.1.")
    sdk_root = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    require(sdk_root, "Android SDK location is missing.")
    sdk_tools = Path(sdk_root) / "build-tools/36.0.0"
    require((sdk_tools / "aapt2").is_file() and (sdk_tools / "apksigner").is_file(),
            "Install Android SDK build-tools 36.0.0 in the CI image before running.")
    report["tools"] = {"flutter": flutter["frameworkVersion"], "dart": flutter.get("dartSdkVersion"),
                       "java": run(["java", "-version"]).strip(), "buildTools": "36.0.0", "bundletool": "1.18.3"}
    require(re.search(r'version "17[.\"]', report["tools"]["java"]), "Expected Java 17.")
    lock_hash = digest(Path("pubspec.lock"))
    with tempfile.TemporaryDirectory(prefix="polevaya-signing-") as temp:
        directory = Path(temp)
        environments = {store: signing_env(store, directory) for store in selected}
        clean_env = {key: value for key, value in os.environ.items()
                     if not key.startswith("ANDROID_UPLOAD_") and not key.startswith("ANDROID_APP_SIGNING_")}
        run(["flutter", "pub", "get", "--enforce-lockfile"], clean_env)
        require(digest(Path("pubspec.lock")) == lock_hash, "Dependency resolution changed pubspec.lock.")
        print("Analyzing Flutter; automated tests are not enabled.", flush=True)
        run(["flutter", "analyze", "--no-pub"], clean_env)
        bundle = directory / "bundletool.jar"
        if "google_play" in selected:
            with urllib.request.urlopen(BUNDLE_URL, timeout=60) as response:
                bundle.write_bytes(response.read())
            require(digest(bundle) == BUNDLE_HASH, "bundletool download checksum mismatch.")
        artifacts = []
        for store in selected:
            report["step"] = store
            target, source, suffix = ("appbundle", "build/app/outputs/bundle/release/app-release.aab", "aab") if store == "google_play" else (
                "apk", "build/app/outputs/flutter-apk/app-release.apk", "apk")
            print(f"Preparing {store} from {commit}.", flush=True)
            # Implicit pub regenerates release plugin registrant in Flutter 3.47.
            run(["flutter", "build", target, "--release", "--dart-define=APP_ENV=prod",
                 f"--dart-define=API_BASE_URL={API}", f"--dart-define=DATA_BASE_URL={DATA}",
                 f"--dart-define=APP_VERSION_URL={VERSION_URL}"], environments[store])
            require(digest(Path("pubspec.lock")) == lock_hash, "Build changed pubspec.lock.")
            artifact = directory / f"{store}-{version}+{build}.{suffix}"
            shutil.copyfile(source, artifact)
            verify(store, artifact, version, build, sdk_tools, bundle)
            report["channels"][store] = {"status": "built", "artifact": artifact.name,
                                         "sha256": digest(artifact), "certificateSha256": CERTS[store]}
            artifacts.append(artifact)
        require(run(["git", "rev-parse", "HEAD"]).strip() == commit and identity() == (version, build), "Source identity changed during preparation.")
        require(not run(["git", "status", "--porcelain", "--untracked-files=no"]).strip(), "Build changed tracked source files.")
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for artifact in artifacts:
            shutil.copyfile(artifact, OUTPUT / artifact.name)
    report.update(status="prepared", step="complete", lockfileSha256=lock_hash)
    (OUTPUT / "SHA256SUMS.txt").write_text("".join(
        f"{data['sha256']}  {data['artifact']}\n" for data in report["channels"].values()))


def main():
    report = {"status": "failed", "mode": "prepare", "package": PACKAGE,
              "startedAtUtc": datetime.now(timezone.utc).isoformat(),
              "storeUploadPerformed": False, "storeVersionAvailabilityChecked": False}
    try:
        prepare(report)
        print("All selected Android artifacts verified; no store upload performed.")
    except PreparationError as error:
        report["reason"] = str(error)
        print(f"Preparation stopped: {error}")
    except Exception as error:
        report["reason"] = f"Preparation stopped ({type(error).__name__}); sensitive diagnostics suppressed."
        print(report["reason"])
    finally:
        report["finishedAtUtc"] = datetime.now(timezone.utc).isoformat()
        OUTPUT.mkdir(parents=True, exist_ok=True)
        (OUTPUT / "release-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if report["status"] == "prepared" else 1


if __name__ == "__main__":
    raise SystemExit(main())
