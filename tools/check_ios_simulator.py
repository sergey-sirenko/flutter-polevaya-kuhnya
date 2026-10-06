"""Launch the fixed Simulator 72 artifact; anonymous screens only, no rebuild."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import zipfile
import urllib.request
import urllib.parse

from prepare_android_ci import digest, require
from prepare_ios_ci import BUNDLE
from upload_existing_ios import download_artifact, safe_apple_diagnostics

OUTPUT = Path("build/release/ios-simulator-smoke")
NAVIGATION = "--navigation" in sys.argv[1:]
STORE_SHOTS = "--store-screenshots" in sys.argv[1:]
NAVIGATION = NAVIGATION or STORE_SHOTS
if NAVIGATION:
    OUTPUT = Path("build/release/ios-simulator-navigation")
if STORE_SHOTS:
    OUTPUT = Path("build/release/ios-store-screenshots")
URL = ("https://api.codemagic.io/artifacts/8c12313f-674f-43c0-a5bd-312e5f808c4b/"
       "dc8798d2-281e-4b86-8410-0101b97acb9f/ios-simulator-1.0.072.zip")
SHA = "a7df177db6f5b19e9558da54f90c024648e954072d03d9b5615e7782c8091b35"


def hide_banner(logs):
    """Use the running app's authenticated loopback VM service, no image edits."""
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        text = "\n".join(p.read_text(encoding="utf-8", errors="replace")
                         for p in logs if p.exists())
        uris = re.findall(r"http://(?:127\.0\.0\.1|localhost):\d+/[A-Za-z0-9_=-]+/", text)
        for uri in reversed(uris):
            def rpc(method, **params):
                request = uri + method + "?" + urllib.parse.urlencode(params)
                with urllib.request.urlopen(request, timeout=5) as response:
                    result = json.load(response)
                require("error" not in result, "VM service rejected screenshot configuration.")
                return result["result"]
            try:
                for isolate in rpc("getVM").get("isolates", []):
                    details = rpc("getIsolate", isolateId=isolate["id"])
                    if "ext.flutter.debugAllowBanner" in details.get("extensionRPCs", []):
                        result = rpc("ext.flutter.debugAllowBanner", isolateId=isolate["id"], enabled="false")
                        require(str(result.get("enabled")).lower() == "false", "Banner state not confirmed.")
                        time.sleep(2)
                        return
            except (OSError, KeyError, ValueError):
                pass
        time.sleep(1)
    raise RuntimeError("Cannot reach Flutter banner extension; no clean screenshots produced.")


def command(args, env, report, timeout=180):
    result = subprocess.run(args, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    output = result.stdout.decode("utf-8", errors="replace")
    with (OUTPUT / "commands.txt").open("a", encoding="utf-8") as stream:
        stream.write(safe_apple_diagnostics(" ".join(args) + "\n" + output) + "\n")
    require(result.returncode == 0, f"Command failed: {args[0]} {args[1]}; exit {result.returncode}.")
    return output


def main():
    OUTPUT.mkdir(parents=True, exist_ok=False)
    report = dict(status="failed", startedAtUtc=datetime.now(timezone.utc).isoformat(),
                  version="1.0.0", buildNumber="72", archiveSha256=SHA, devices=[],
                  appRebuilt=False, storeUploadPerformed=False, appleApiCalled=False,
                  authenticatedScenariosRun=False, orderMutationsPerformed=False,
                  physicalDeviceAcceptance=False, acceptanceStatus="not_tested")
    env = {k: v for k, v in os.environ.items() if not k.startswith(
        ("IOS_", "ANDROID_", "APP_STORE_CONNECT_", "GOOGLE_PLAY_", "CODEMAGIC_ARTIFACT_"))}
    created = []
    try:
        require(sys.platform == "darwin" and os.environ.get("CM_BUILD_ID"), "Run on Codemagic macOS.")
        sim = lambda *args: ["xcrun", "simctl", *args]
        inventory = json.loads(command(sim("list", "--json"), env, report))
        runtimes = [r for r in inventory["runtimes"] if r.get("isAvailable")
                    and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
        require(runtimes, "No available iOS Simulator runtime.")
        runtime = max(runtimes, key=lambda r: tuple(int(n) for n in r["version"].split(".")))
        report.update(runtime=runtime["identifier"], runtimeVersion=runtime["version"])
        types = inventory["devicetypes"]
        with tempfile.TemporaryDirectory(prefix="ios72-smoke-") as temporary:
            root = Path(temporary)
            archive = root / "simulator.zip"
            download_artifact(URL, archive, report)
            require(digest(archive) == SHA, "Simulator archive checksum mismatch.")
            with zipfile.ZipFile(archive) as zipped:
                require(all(not Path(n).is_absolute() and ".." not in Path(n).parts
                            for n in zipped.namelist()), "Unsafe archive path.")
            command(["ditto", "-x", "-k", str(archive), str(root / "app")], env, report)
            app = root / "app/Runner.app"
            info = plistlib.loads((app / "Info.plist").read_bytes())
            require(info.get("CFBundleIdentifier") == BUNDLE and info.get("CFBundleVersion") == "72"
                    and info.get("CFBundleShortVersionString") == "1.0.0"
                    and info.get("DTPlatformName") == "iphonesimulator", "Wrong app identity/platform.")
            if NAVIGATION:
                from ios_simulator_navigation import install_maestro, run_navigation
                maestro = install_maestro(root, env, command, report)
            models = [("iPhone", "iPhone 16 Pro Max"), ("iPad", "iPad Pro 13-inch (M4)")] if STORE_SHOTS else [("iPhone", "iPhone 16"), ("iPad", "iPad (A16)")]
            for family, preferred in models:
                candidates = [d for d in types if d["name"].startswith(family)]
                require(candidates, f"No {family} Simulator device type.")
                device_type = next((d for d in candidates if d["name"] == preferred), candidates[-1])
                require(not STORE_SHOTS or device_type["name"] == preferred, "Required store screenshot device unavailable.")
                udid = command(sim("create", f"Polevaya72-{family}", device_type["identifier"],
                                   runtime["identifier"]), env, report).strip()
                require(re.fullmatch(r"[0-9A-Fa-f-]{36}", udid), "Invalid created simulator UUID.")
                created.append(udid)
                device = dict(family=family, model=device_type["name"], udid=udid, status="starting")
                report["devices"].append(device)
                command(sim("boot", udid), env, report)
                command(sim("bootstatus", udid, "-b"), env, report, timeout=360)
                command(sim("install", udid, str(app)), env, report)
                stdout = (OUTPUT / f"{family}-stdout.txt").resolve()
                stderr = (OUTPUT / f"{family}-stderr.txt").resolve()
                def launch():
                    text = command(sim("launch", f"--stdout={stdout}", f"--stderr={stderr}",
                                       udid, BUNDLE, *(["--enable-checked-mode", "--verify-entry-points", "--vm-service-port=54321"] if STORE_SHOTS else [])), env, report)
                    match = re.search(re.escape(BUNDLE) + r":\s*(\d+)", text)
                    require(match, "Simulator did not return app PID.")
                    return match.group(1)
                pid = launch()
                if STORE_SHOTS:
                    hide_banner([stdout, stderr])
                time.sleep(10)
                command(sim("io", udid, "screenshot", str(OUTPUT / f"{family}-launch.png")), env, report)
                time.sleep(20)
                require(launch() == pid, f"{family} app process changed during the launch observation.")
                command(sim("io", udid, "screenshot", str(OUTPUT / f"{family}-settled.png")), env, report)
                command(sim("terminate", udid, BUNDLE), env, report)
                relaunch_pid = launch()
                if STORE_SHOTS:
                    hide_banner([stdout, stderr])
                    device["debugBannerDisabledViaVmService"] = True
                time.sleep(15)
                require(launch() == relaunch_pid, f"{family} app did not remain running after relaunch.")
                command(sim("io", udid, "screenshot", str(OUTPUT / f"{family}-relaunch.png")), env, report)
                device.update(status="captured", processStableDuringObservation=True,
                              relaunchProcessStable=True, visualReview="pending")
                if NAVIGATION:
                    run_navigation(maestro, udid, family, env, command, report, OUTPUT, store_shots=STORE_SHOTS)
                    device["navigationStatus"] = "assertions_passed_pending_visual_review"
                command(sim("shutdown", udid), env, report)
        report.update(status="captured", acceptanceStatus="pending_visual_review")
        return 0
    except Exception as error:
        report["error"] = safe_apple_diagnostics(str(error))
        print(report["error"], file=sys.stderr)
        return 1
    finally:
        for udid in created:
            for action in ("shutdown", "delete"):
                try:
                    subprocess.run(["xcrun", "simctl", action, udid], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
                except subprocess.TimeoutExpired:
                    report.setdefault("cleanupWarnings", []).append(f"{action} timed out for {udid}")
        # Only anonymous launches are exercised; redact credentials/URLs from captured logs.
        for log in OUTPUT.glob("*.txt"):
            sanitized = re.sub(r"http://(?:127\.0\.0\.1|localhost):\d+/[^\s]+", "[local VM service]", log.read_text(encoding="utf-8", errors="replace"))
            log.write_text(safe_apple_diagnostics(sanitized),
                           encoding="utf-8")
        report["finishedAtUtc"] = datetime.now(timezone.utc).isoformat()
        name = "navigation-report.json" if NAVIGATION else "smoke-report.json"
        report["navigationRequested"] = NAVIGATION
        (OUTPUT / name).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
