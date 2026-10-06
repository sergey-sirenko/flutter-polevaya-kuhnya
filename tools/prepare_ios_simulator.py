"""Prepare the accepted iOS 72 sources for manual Simulator acceptance."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

from prepare_android_ci import API, DATA, VERSION_URL, digest, require
from prepare_ios_ci import BUNDLE, version
from upload_existing_ios import safe_apple_diagnostics

SOURCE = "f47895509bcf1da287accb68f45b27acdff63d25"
OUTPUT = Path("build/release/ios-simulator")
APP = Path("build/ios/iphonesimulator/Runner.app")


def run(args, env):
    result = subprocess.run(args, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=2400)
    output = result.stdout.decode("utf-8", errors="replace")
    if result.returncode:
        print(safe_apple_diagnostics(output), file=sys.stderr)
    require(result.returncode == 0, f"Command failed: {args[0]} {args[1]}; exit {result.returncode}.")
    return output


def prepare(report):
    require(sys.platform == "darwin" and os.environ.get("CM_BUILD_ID"),
            "Run on a fresh Codemagic macOS machine.")
    env = {k: v for k, v in os.environ.items() if not k.startswith(
        ("IOS_", "ANDROID_", "APP_STORE_CONNECT_", "GOOGLE_PLAY_", "CODEMAGIC_ARTIFACT_"))}
    report["workflowCommit"] = run(["git", "rev-parse", "HEAD"], env).strip()
    require(not run(["git", "status", "--porcelain", "--untracked-files=no"], env).strip(),
            "Tracked checkout must be clean.")
    require(not APP.exists(), "Use a fresh checkout without a previous simulator app.")
    # CI changes may advance HEAD; app sources must stay identical to IPA 72.
    run(["git", "fetch", "--no-tags", "origin", SOURCE], env)
    require(not run(["git", "diff", SOURCE, "HEAD", "--", "lib", "assets", "ios",
                     "pubspec.yaml", "pubspec.lock"], env).strip(),
            "Application sources differ from the accepted IPA 72 source.")
    require(version() == ("1.0.0", "72"), "Expected accepted version 1.0.0+72.")
    report.update(sourceCommit=SOURCE, version="1.0.0", buildNumber="72",
                  lockfileSha256=digest(Path("pubspec.lock")), configuration="Debug",
                  environment="prod", acceptanceStatus="not_tested",
                  physicalDeviceAcceptance=False, storeUploadPerformed=False,
                  appTestsRun=False, previewSessionStarted=False)
    run(["flutter", "pub", "get", "--enforce-lockfile"], env)
    run(["flutter", "build", "ios", "--debug", "--simulator", "--no-codesign", "--no-pub",
         "--dart-define=APP_ENV=prod", f"--dart-define=API_BASE_URL={API}",
         f"--dart-define=DATA_BASE_URL={DATA}", f"--dart-define=APP_VERSION_URL={VERSION_URL}"], env)
    info = plistlib.loads((APP / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == BUNDLE
            and info.get("CFBundleShortVersionString") == "1.0.0"
            and info.get("CFBundleVersion") == "72", "Simulator bundle/version mismatch.")
    require(info.get("DTPlatformName") == "iphonesimulator", "Expected Simulator platform.")
    require(set(info.get("UIDeviceFamily", [])) == {1, 2}, "Expected iPhone and iPad support.")
    require(set(info.get("UISupportedInterfaceOrientations~ipad", [])) == {
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"},
        "Expected all four iPad orientations.")
    archive = OUTPUT / "ios-simulator-1.0.0+72.zip"
    run(["ditto", "-c", "-k", "--keepParent", str(APP), str(archive)], env)
    report.update(status="prepared", bundleId=BUNDLE, archiveSha256=digest(archive),
                  deviceFamilies=info["UIDeviceFamily"], platform=info["DTPlatformName"])


def main():
    OUTPUT.mkdir(parents=True, exist_ok=False)
    report = {"status": "failed", "startedAtUtc": datetime.now(timezone.utc).isoformat()}
    try:
        prepare(report)
        return 0
    except Exception as error:
        report["errorType"] = type(error).__name__
        report["error"] = safe_apple_diagnostics(str(error))
        print(report["error"], file=sys.stderr)
        return 1
    finally:
        report["finishedAtUtc"] = datetime.now(timezone.utc).isoformat()
        (OUTPUT / "simulator-report.json").write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
