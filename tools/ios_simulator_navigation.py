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


def png_dimensions(path):
    """Return displayed dimensions, accounting for Maestro PNG eXIf rotation."""
    data = path.read_bytes()
    require(data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24, "Invalid screenshot PNG.")
    width, height = struct.unpack(">II", data[16:24])
    require(width > 0 and height > 0, "Invalid screenshot dimensions.")
    orientation = 1
    position = 8
    while position + 12 <= len(data):
        size = struct.unpack(">I", data[position:position + 4])[0]
        require(position + size + 12 <= len(data), "Truncated screenshot PNG chunk.")
        kind = data[position + 4:position + 8]
        if kind == b"eXIf":
            tiff = data[position + 8:position + 8 + size]
            require(len(tiff) >= 8 and tiff[:2] in (b"MM", b"II"), "Invalid screenshot EXIF.")
            endian = ">" if tiff[:2] == b"MM" else "<"
            require(struct.unpack(endian + "H", tiff[2:4])[0] == 42, "Invalid TIFF header.")
            offset = struct.unpack(endian + "I", tiff[4:8])[0]
            require(offset + 2 <= len(tiff), "Invalid EXIF directory offset.")
            count = struct.unpack(endian + "H", tiff[offset:offset + 2])[0]
            require(offset + 2 + count * 12 <= len(tiff), "Truncated EXIF directory.")
            for index in range(count):
                entry = offset + 2 + index * 12
                tag, datatype, length = struct.unpack(endian + "HHI", tiff[entry:entry + 8])
                if tag == 0x0112:
                    require(datatype == 3 and length == 1, "Unexpected EXIF orientation format.")
                    orientation = struct.unpack(endian + "H", tiff[entry + 8:entry + 10])[0]
                    require(1 <= orientation <= 8, "Invalid EXIF orientation value.")
        position += size + 12
    displayed = [height, width] if orientation in (5, 6, 7, 8) else [width, height]
    return dict(rawDimensions=[width, height], exifOrientation=orientation,
                displayDimensions=displayed)


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


def run_navigation(maestro, udid, family, env, command, report, output, store_shots=False, store_size=None):
    folder = (output / family).resolve()
    folder.mkdir()
    steps = [
        {"assertVisible": "Полевая кухня"},
        {"tapOn": "Разделы сайта"},
        {"tapOn": "Меню"},
        {"extendedWaitUntil": {"visible": "Чтобы выбрать блюда, войдите в аккаунт.", "timeout": 60000}},
        {"takeScreenshot": "00-menu-dishes"},
    ]
    if family == "iPhone":
        # Observed +72 accessibility tree: date occurs in the selection heading
        # and then in the bottom navigation. Tap the second occurrence, not a
        # fixed production date or a screen coordinate.
        steps.extend([
            {"tapOn": {"text": "(Пн|Вт|Ср|Чт|Пт|Сб|Вс) [0-9]{2}\\.[0-9]{2}", "index": 1}},
            {"assertVisible": "День"},
        ])
    steps.extend([
        {"extendedWaitUntil": {"visible": "Текущая неделя", "timeout": 60000}},
        {"takeScreenshot": "01-menu-current"},
        {"tapOn": "Текущая неделя"},
        {"assertVisible": "Текущая неделя"},
    ])
    if family == "iPhone":
        steps.extend([
            {"tapOn": "Закрыть"},
            {"assertVisible": "Чтобы выбрать блюда, войдите в аккаунт."},
            {"takeScreenshot": "02-menu-after-current-week-selection"},
        ])
    if family == "iPad":
        for orientation in ["LANDSCAPE_LEFT", "LANDSCAPE_RIGHT", "UPSIDE_DOWN", "PORTRAIT"]:
            steps.extend([{"setOrientation": orientation},
                          {"assertVisible": "Текущая неделя"},
                          {"takeScreenshot": "03-menu-" + orientation.lower()}])
    report["weekCheckScope"] = "current_week_only_owner_requested"
    # The order screen's nested Scaffold omits the outer brand from Maestro's
    # accessibility hierarchy. Use its observed portrait screenshot location;
    # all iPad rotations finish in PORTRAIT before this action.
    home_point = "20%,11%" if family == "iPhone" else "15%,6%"
    report.setdefault("coordinateFallbacks", []).append(
        {"family": family, "action": "order_header_brand_home", "point": home_point})
    steps.extend([
        {"tapOn": {"point": home_point}},
        {"assertVisible": "Заказать обед"},
        {"tapOn": "Разделы сайта"},
        {"tapOn": "Доставка"},
        {"extendedWaitUntil": {"visible": "Условия доставки", "timeout": 30000}},
        {"takeScreenshot": "04-delivery"},
        {"tapOn": "Полевая кухня"},
        {"assertVisible": "Заказать обед"},
        {"takeScreenshot": "05-home-return"},
    ])
    if store_shots:
        steps = [
            {"assertVisible": "Заказать обед"},
            {"takeScreenshot": "home"},
            {"tapOn": "Разделы сайта"},
            {"tapOn": "Меню"},
            {"extendedWaitUntil": {"visible": "Чтобы выбрать блюда, войдите в аккаунт.", "timeout": 60000}},
            {"takeScreenshot": "menu"},
            {"tapOn": {"point": home_point}},
            {"assertVisible": "Заказать обед"},
            {"tapOn": "Разделы сайта"},
            {"tapOn": "Доставка"},
            {"extendedWaitUntil": {"visible": "Условия доставки", "timeout": 30000}},
            {"takeScreenshot": "delivery"},
        ]
    flow = folder / "flow.yaml"
    # JSON values are valid YAML; preserve Unicode labels, no external parser needed.
    flow.write_text("appId: " + BUNDLE + "\n---\n" +
                    "\n".join("- " + json.dumps(step, ensure_ascii=False) for step in steps) + "\n",
                    encoding="utf-8")
    try:
        command([maestro, "--device", udid, "test", "--format", "junit",
                 "--output", str(folder / "junit.xml"), "--test-output-dir", str(folder),
                 "--debug-output", str(folder / "debug"), str(flow)], env, report, timeout=900)
        if store_shots:
            expected = store_size or ([1320, 2868] if family == "iPhone" else [2064, 2752])
            for name in ["home", "menu", "delivery"]:
                files = list(folder.rglob(name + ".png"))
                require(len(files) == 1, "Missing or ambiguous store screenshot.")
                require(png_dimensions(files[0])["displayDimensions"] == expected, "Wrong store screenshot size.")
        elif family == "iPad":
            dimensions = {}
            metadata = {}
            for orientation in ["landscape_left", "landscape_right", "upside_down", "portrait"]:
                images = list(folder.rglob("03-menu-" + orientation + ".png"))
                require(len(images) == 1, "Expected orientation screenshot missing or ambiguous.")
                metadata[orientation] = png_dimensions(images[0])
                width, height = metadata[orientation]["displayDimensions"]
                require((width > height) if orientation.startswith("landscape") else (height > width),
                        "Screenshot dimensions do not match requested orientation.")
                dimensions[orientation] = [width, height]
            report["iPadOrientationScreenshotDimensions"] = dimensions
            report["iPadOrientationScreenshotMetadata"] = metadata
    finally:
        for path in folder.rglob("*"):
            if path.is_file() and path.suffix in (".log", ".txt", ".json", ".xml"):
                path.write_text("\n".join(safe_apple_diagnostics(line) for line in
                                path.read_text(encoding="utf-8", errors="replace").splitlines()) + "\n",
                                encoding="utf-8")
