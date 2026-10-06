"""Pinned local Maestro UI checks; no cloud, accounts or order writes."""
import json
from pathlib import Path
import struct
import urllib.request
import zipfile

from prepare_android_ci import digest, require
from prepare_ios_ci import BUNDLE
from upload_existing_ios import safe_apple_diagnostics

VERSION = "2.11.0"
URL = f"https://github.com/mobile-dev-inc/Maestro/releases/download/cli-{VERSION}/maestro.zip"
SHA = "5384593cb4e7a106489e75a821d157dd43f4e438df6bc308b72e82c685e1283a"


def install_maestro(root, env, command, report):
    env.update(MAESTRO_CLI_NO_ANALYTICS="true", MAESTRO_DISABLE_UPDATE_CHECK="true",
               MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED="true",
               MAESTRO_DRIVER_STARTUP_TIMEOUT="120000")
    env.pop("MAESTRO_CLOUD_API_KEY", None)
    java = command(["/usr/libexec/java_home", "-v", "17"], env, report).strip()
    env["JAVA_HOME"] = java
    env["PATH"] = str(Path(java) / "bin") + ":" + env["PATH"]
    archive = root / "maestro.zip"
    # Public GitHub download: no Codemagic or Apple credentials in this request.
    with urllib.request.urlopen(URL, timeout=120) as response, archive.open("wb") as target:
        require(response.geturl().startswith("https://"), "Non-HTTPS Maestro download.")
        size = 0
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            require(size <= 400 * 1024 * 1024, "Maestro archive exceeds size limit.")
            target.write(chunk)
    require(digest(archive) == SHA, "Maestro archive checksum mismatch.")
    with zipfile.ZipFile(archive) as zipped:
        require(all(not Path(n).is_absolute() and ".." not in Path(n).parts
                    for n in zipped.namelist()), "Unsafe Maestro archive path.")
    directory = root / "maestro-cli"
    command(["ditto", "-x", "-k", str(archive), str(directory)], env, report)
    executables = list(directory.glob("**/bin/maestro"))
    require(len(executables) == 1, "Maestro executable missing or ambiguous.")
    executable = str(executables[0])
    actual = command([executable, "--version"], env, report).strip()
    require(actual == VERSION, "Unexpected Maestro CLI version.")
    report.update(maestroVersion=actual, maestroArchiveSha256=SHA,
                  maestroCloudUsed=False, telemetryDisabled=True)
    return executable


def run_navigation(maestro, udid, family, env, command, report, output):
    folder = (output / family).resolve()
    folder.mkdir()
    steps = [
        {"assertVisible": "Полевая кухня"},
        {"tapOn": "Разделы сайта"},
        {"tapOn": "Меню"},
        {"extendedWaitUntil": {"visible": "Текущая неделя", "timeout": 60000}},
        {"assertVisible": "Следующая неделя"},
        {"takeScreenshot": "01-menu-current"},
        {"tapOn": "Следующая неделя"},
        {"assertVisible": "Текущая неделя"},
        {"takeScreenshot": "02-menu-next"},
        {"tapOn": "Текущая неделя"},
    ]
    if family == "iPad":
        for orientation in ["LANDSCAPE_LEFT", "LANDSCAPE_RIGHT", "UPSIDE_DOWN", "PORTRAIT"]:
            steps.extend([{"setOrientation": orientation},
                          {"assertVisible": "Текущая неделя"},
                          {"assertVisible": "Следующая неделя"},
                          {"takeScreenshot": "03-menu-" + orientation.lower()}])
    steps.extend([
        {"tapOn": "Полевая кухня"},
        {"assertVisible": "Заказать обед"},
        {"tapOn": "Разделы сайта"},
        {"tapOn": "Доставка"},
        {"extendedWaitUntil": {"visible": "Условия доставки", "timeout": 30000}},
        {"takeScreenshot": "04-delivery"},
        {"tapOn": "Полевая кухня"},
        {"assertVisible": "Заказать обед"},
        {"takeScreenshot": "05-home-return"},
    ])
    flow = folder / "flow.yaml"
    # JSON values are valid YAML; preserve Unicode labels, no external parser needed.
    flow.write_text("appId: " + BUNDLE + "\n---\n" +
                    "\n".join("- " + json.dumps(step, ensure_ascii=False) for step in steps) + "\n",
                    encoding="utf-8")
    try:
        command([maestro, "--device", udid, "test", "--format", "junit",
                 "--output", str(folder / "junit.xml"), "--test-output-dir", str(folder),
                 "--debug-output", str(folder / "debug"), str(flow)], env, report, timeout=900)
        if family == "iPad":
            dimensions = {}
            for orientation in ["landscape_left", "landscape_right", "upside_down", "portrait"]:
                images = list(folder.rglob("03-menu-" + orientation + ".png"))
                require(len(images) == 1, "Expected orientation screenshot missing or ambiguous.")
                header = images[0].read_bytes()[:24]
                require(header[:8] == b"\x89PNG\r\n\x1a\n", "Invalid screenshot PNG.")
                width, height = struct.unpack(">II", header[16:24])
                require((width > height) if orientation.startswith("landscape") else (height > width),
                        "Screenshot dimensions do not match requested orientation.")
                dimensions[orientation] = [width, height]
            report["iPadOrientationScreenshotDimensions"] = dimensions
    finally:
        for path in folder.rglob("*"):
            if path.is_file() and path.suffix in (".log", ".txt", ".json", ".xml"):
                path.write_text("\n".join(safe_apple_diagnostics(line) for line in
                                path.read_text(encoding="utf-8", errors="replace").splitlines()) + "\n",
                                encoding="utf-8")
