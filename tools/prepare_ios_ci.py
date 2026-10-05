"""Signed IPA preparation only; no App Store credentials or upload."""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from prepare_android_ci import (API, DATA, VERSION_URL, PreparationError,
                                digest, get_json, require, run)

BUNDLE = "ru.obedmoscow.polevayakuhnya"
TEAM = "F8BS872XC2"
CERT_SHA1 = "0556df536ee5f42d407b48b6029fce1fd1ed5e37"
OUTPUT = Path("build/release/ios")
PROJECT = Path("ios/Runner.xcodeproj/project.pbxproj")


def version():
    match = re.findall(r"^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$",
                       Path("pubspec.yaml").read_text(), re.M)
    require(len(match) == 1, "Expected one pubspec version X.Y.Z+N.")
    name, build = match[0]
    require(int(build) <= 9999, "Single-component iOS build number must be <= 9999.")
    return name, build


def decode_profile(path, env):
    result = subprocess.run(["security", "cms", "-D", "-i", str(path)], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    require(result.returncode == 0, "Cannot decode provisioning profile.")
    return plistlib.loads(result.stdout)


def check_profile(profile):
    entitlements = profile.get("Entitlements", {})
    require(profile.get("TeamIdentifier") == [TEAM], "Wrong profile Team.")
    require(entitlements.get("application-identifier") == f"{TEAM}.{BUNDLE}", "Wrong profile App ID.")
    require(entitlements.get("get-task-allow") is False and not profile.get("ProvisionedDevices")
            and not profile.get("ProvisionsAllDevices"), "Expected App Store distribution profile.")
    expiry = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    require(expiry > datetime.now(timezone.utc), "Provisioning profile expired.")
    require(CERT_SHA1 in [hashlib.sha1(c).hexdigest() for c in profile["DeveloperCertificates"]],
            "Profile does not contain the accepted signing certificate.")
    require(re.fullmatch(r"[0-9a-fA-F-]{36}", profile.get("UUID", "")), "Invalid profile UUID.")


def verify_ipa(ipa, directory, profile, name, build, env):
    unpack = directory / "ipa"
    with zipfile.ZipFile(ipa) as archive:
        for member in archive.infolist():
            require(not Path(member.filename).is_absolute() and ".." not in Path(member.filename).parts,
                    "Unsafe IPA archive path.")
        archive.extractall(unpack)
    apps = list((unpack / "Payload").glob("*.app"))
    require(len(apps) == 1, "IPA must contain one app.")
    app = apps[0]
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == BUNDLE and info.get("CFBundleShortVersionString") == name
            and info.get("CFBundleVersion") == build, "IPA bundle/version differs from pubspec.")
    embedded = decode_profile(app / "embedded.mobileprovision", env)
    check_profile(embedded)
    require(embedded["UUID"] == profile["UUID"], "Unexpected embedded profile.")
    run(["codesign", "--verify", "--deep", "--strict", str(app)], env)
    prefix = directory / "signer"
    run(["codesign", "-d", "--extract-certificates", str(prefix), str(app)], env)
    require(hashlib.sha1(Path(str(prefix) + "0").read_bytes()).hexdigest() == CERT_SHA1,
            "IPA signer differs from accepted certificate.")


def prepare(report):
    require(sys.platform == "darwin" and os.environ.get("CM_BUILD_ID"), "Run only on a fresh Codemagic macOS machine.")
    commit = os.environ.get("RELEASE_COMMIT", "").strip().lower()
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "Specify full accepted commit SHA.")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("IOS_", "ANDROID_", "GOOGLE_PLAY_"))}
    require(run(["git", "rev-parse", "HEAD"], env).strip() == commit, "Checkout does not match accepted SHA.")
    require(not run(["git", "status", "--porcelain", "--untracked-files=no"], env).strip(), "Tracked checkout is dirty.")
    require(not OUTPUT.exists(), "Use a fresh checkout without release output.")
    name, build = version()
    notes = os.environ.get("RELEASE_NOTES", "").strip()
    require(0 < len(notes) <= 500, "Release notes must contain 1–500 characters.")
    report.update(commit=commit, version=name, buildNumber=build, releaseNotes=notes)
    policy = get_json(VERSION_URL)
    require(policy.get("policy", {}).get("schema") == 1 and policy["policy"].get("environment") == "prod",
            "Invalid production version policy.")
    require(isinstance(get_json(DATA + "dishes.json"), (dict, list)), "Invalid production menu.")
    import socket
    import ssl
    with socket.create_connection(("hleb-sol.su", 443), timeout=20) as connection:
        with ssl.create_default_context().wrap_socket(connection, server_hostname="hleb-sol.su"):
            pass
    flutter = json.loads(run(["flutter", "--version", "--machine"], env))
    require(flutter.get("frameworkVersion") == "3.47.1", "Expected Flutter 3.47.1.")
    xcode = run(["xcodebuild", "-version"], env).strip()
    require(xcode.startswith("Xcode 26.6\n"), "Expected Xcode 26.6.")
    report["tools"] = {"flutter": flutter["frameworkVersion"], "xcode": xcode,
                       "codemagicCli": run(["xcode-project", "--version"], env).strip()}
    lock = digest(Path("pubspec.lock"))
    original_project = PROJECT.read_bytes()
    installed_profile = None
    profile_created = False
    keychain_ready = False
    with tempfile.TemporaryDirectory(prefix="polevaya-ios-") as tmp:
        directory = Path(tmp)
        keychain_path = directory / "release.keychain-db"
        try:
            for variable, filename in [("IOS_DISTRIBUTION_P12_BASE64", "certificate.p12"),
                                       ("IOS_PROVISIONING_PROFILE_BASE64", "profile.mobileprovision")]:
                require(os.environ.get(variable), f"Missing Secret: {variable}.")
                data = base64.b64decode(os.environ[variable], validate=True)
                with os.fdopen(os.open(directory / filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
                    stream.write(data)
            require(os.environ.get("IOS_DISTRIBUTION_P12_PASSWORD"), "Missing P12 password Secret.")
            profile = decode_profile(directory / "profile.mobileprovision", env)
            check_profile(profile)
            report["profileUuid"] = profile["UUID"]
            run(["keychain", "initialize", "--path", str(keychain_path)], env)
            keychain_ready = True
            signing_env = dict(env, P12_PASSWORD=os.environ["IOS_DISTRIBUTION_P12_PASSWORD"])
            run(["keychain", "add-certificates", "--path", str(keychain_path), "--certificate", str(directory / "certificate.p12"),
                 "--certificate-password", "@env:P12_PASSWORD"], signing_env)
            profile_dir = Path.home() / "Library/MobileDevice/Provisioning Profiles"
            profile_dir.mkdir(parents=True, exist_ok=True)
            installed_profile = profile_dir / f"{profile['UUID']}.mobileprovision"
            require(not installed_profile.exists(), "Profile already exists on machine; refusing overwrite.")
            with os.fdopen(os.open(installed_profile, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
                profile_created = True
                stream.write((directory / "profile.mobileprovision").read_bytes())
            run(["flutter", "pub", "get", "--enforce-lockfile"], env)
            require(digest(Path("pubspec.lock")) == lock, "pubspec.lock changed.")
            run(["flutter", "analyze", "--no-pub"], env)
            options = directory / "export_options.plist"
            run(["xcode-project", "use-profiles", "--project", "ios/Runner.xcodeproj",
                 "--profile", str(installed_profile), "--export-options-plist", str(options),
                 "--custom-export-options", '{"manageAppVersionAndBuildNumber":false,"destination":"export"}'], env)
            report["step"] = "build"
            run(["flutter", "build", "ipa", "--release", "--export-options-plist", str(options),
                 "--dart-define=APP_ENV=prod", f"--dart-define=API_BASE_URL={API}",
                 f"--dart-define=DATA_BASE_URL={DATA}", f"--dart-define=APP_VERSION_URL={VERSION_URL}"], env)
            require(digest(Path("pubspec.lock")) == lock and version() == (name, build), "Build changed version or lockfile.")
            ipas = list(Path("build/ios/ipa").glob("*.ipa"))
            require(len(ipas) == 1, "Expected exactly one exported IPA.")
            verify_ipa(ipas[0], directory, profile, name, build, env)
            PROJECT.write_bytes(original_project)
            require(not run(["git", "status", "--porcelain", "--untracked-files=no"], env).strip(),
                    "Build changed tracked source files beyond temporary signing settings.")
            require(run(["git", "rev-parse", "HEAD"], env).strip() == commit, "Commit changed during build.")
            artifact = f"app_store-{name}+{build}.ipa"
            sha = digest(ipas[0])
            OUTPUT.mkdir(parents=True)
            shutil.copyfile(ipas[0], OUTPUT / artifact)
            (OUTPUT / "SHA256SUMS.txt").write_text(f"{sha}  {artifact}\n")
            report.update(status="prepared", step="complete", lockfileSha256=lock,
                          channels={"app_store": {"status": "built", "artifact": artifact,
                                                  "sha256": sha, "certificateSha1": CERT_SHA1}})
        finally:
            PROJECT.write_bytes(original_project)
            if profile_created and installed_profile is not None and installed_profile.exists():
                installed_profile.unlink()
            if keychain_ready:
                run(["keychain", "delete", "--path", str(keychain_path)], env)


def main():
    report = {"status": "failed", "step": "preflight", "mode": "prepare", "bundleId": BUNDLE,
              "storeUploadPerformed": False, "storeVersionAvailabilityChecked": False,
              "startedAtUtc": datetime.now(timezone.utc).isoformat()}
    try:
        prepare(report)
    except PreparationError as error:
        report.update(status="failed", reason=str(error))
    except Exception as error:
        report.update(status="failed", reason=f"Stopped ({type(error).__name__}); sensitive diagnostics suppressed.")
    finally:
        report["finishedAtUtc"] = datetime.now(timezone.utc).isoformat()
        OUTPUT.mkdir(parents=True, exist_ok=True)
        (OUTPUT / "release-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(report.get("reason", "IPA verified; no store upload performed."))
    return 0 if report["status"] == "prepared" else 1


if __name__ == "__main__":
    raise SystemExit(main())
