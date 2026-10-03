"""Проверка test-policy в version.json и сверка выкладки/отката.

Идентификация сборки — пара version/build. Policy проверяется отдельно и
не отбрасывается сравнением с укороченным JSON. Публикацию скрипт не делает.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

TEST_WEB_URL = "https://flutter-test.obedmoscow.ru/"
ACCEPTED_MINIMUM = ("0.1.0", 1)
_VERSION = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
_PUBSPEC_VERSION = re.compile(
    r"^version:\s*(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)\s*$",
    re.MULTILINE,
)


class PolicyError(Exception):
    pass


def identity(document: dict) -> tuple[str, int]:
    version = document.get("version")
    build = document.get("build")
    if not isinstance(version, str) or _VERSION.fullmatch(version) is None:
        raise PolicyError("version не является тройкой чисел.")
    if type(build) is not int or isinstance(build, bool) or build < 1:
        raise PolicyError("build не является положительным целым.")
    return version, build


def _tuple(version: str, build: int) -> tuple[int, int, int, int]:
    major, minor, patch = (int(part) for part in version.split("."))
    return major, minor, patch, build


def is_forward(old: dict, new: dict) -> bool:
    return _tuple(*identity(old)) < _tuple(*identity(new))


def validate_test_policy(document: dict, expected: tuple[str, int]) -> None:
    version, build = identity(document)
    if (version, build) != expected:
        raise PolicyError("version.json не совпал с pubspec.")
    policy = document.get("policy")
    if not isinstance(policy, dict):
        raise PolicyError("В version.json нет policy.")
    if policy.get("schema") != 1 or policy.get("environment") != "test":
        raise PolicyError("Схема или среда policy не тестовые.")
    minimum = policy.get("minimum")
    if not isinstance(minimum, dict):
        raise PolicyError("Минимум policy не задан.")
    minimum_id = identity({"version": minimum.get("version"), "build": minimum.get("build")})
    if minimum_id != ACCEPTED_MINIMUM:
        raise PolicyError("Тестовый минимум должен остаться 0.1.0+1.")
    releases = policy.get("releases")
    if not isinstance(releases, dict) or set(releases) != {"web", "android", "ios"}:
        raise PolicyError("Нужны ровно три канала выпуска.")
    if releases.get("android") is not None or releases.get("ios") is not None:
        raise PolicyError("Android и iOS в тестовой policy остаются null.")
    web = releases.get("web")
    if not isinstance(web, dict):
        raise PolicyError("Web-выпуск обязателен.")
    web_id = identity({"version": web.get("version"), "build": web.get("build")})
    if web_id != (version, build) or web.get("url") != TEST_WEB_URL:
        raise PolicyError("Web-выпуск не совпал с корнем или тестовым адресом.")
    if _tuple(*minimum_id) > _tuple(*web_id):
        raise PolicyError("Минимум выше Web-выпуска.")


def documents_match(public: dict, expected: dict) -> bool:
    return public == expected


def pubspec_version(text: str) -> tuple[str, int]:
    match = _PUBSPEC_VERSION.search(text)
    if match is None:
        raise PolicyError("В pubspec нет версии major.minor.patch+build.")
    return f"{match.group(1)}.{match.group(2)}.{match.group(3)}", int(match.group(4))


def check_file(version_path: pathlib.Path, pubspec_path: pathlib.Path) -> tuple[str, int]:
    document = json.loads(version_path.read_text(encoding="utf-8"))
    expected = pubspec_version(pubspec_path.read_text(encoding="utf-8"))
    validate_test_policy(document, expected)
    return expected


def _self_test() -> None:
    valid = {
        "version": "0.1.0",
        "build": 15,
        "policy": {
            "schema": 1,
            "environment": "test",
            "minimum": {"version": "0.1.0", "build": 1},
            "releases": {
                "web": {
                    "version": "0.1.0",
                    "build": 15,
                    "url": TEST_WEB_URL,
                },
                "android": None,
                "ios": None,
            },
        },
    }
    validate_test_policy(valid, ("0.1.0", 15))
    legacy = {"version": "0.1.0", "build": 14}
    assert identity(legacy) == ("0.1.0", 14)
    assert is_forward(legacy, valid)
    assert not is_forward(valid, valid)
    assert not is_forward({"version": "0.1.0", "build": 16}, valid)
    assert documents_match(valid, json.loads(json.dumps(valid)))
    assert not documents_match(legacy, valid)
    assert documents_match(legacy, {"version": "0.1.0", "build": 14})
    broken = json.loads(json.dumps(valid))
    broken["policy"]["environment"] = "prod"
    try:
        validate_test_policy(broken, ("0.1.0", 15))
    except PolicyError:
        pass
    else:
        raise AssertionError("prod policy принята")
    broken = json.loads(json.dumps(valid))
    broken["policy"]["releases"]["web"]["build"] = 14
    try:
        validate_test_policy(broken, ("0.1.0", 15))
    except PolicyError:
        pass
    else:
        raise AssertionError("расхождение выпуска принято")
    assert pubspec_version('name: x\nversion: 0.1.0+15\n') == ("0.1.0", 15)
    print("version policy self-test OK")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--version")
    parser.add_argument("--pubspec")
    args = parser.parse_args()
    try:
        if args.self_test:
            _self_test()
            return 0
        if not args.version or not args.pubspec:
            parser.error("Нужны --version и --pubspec либо --self-test.")
        version, build = check_file(pathlib.Path(args.version), pathlib.Path(args.pubspec))
    except (PolicyError, json.JSONDecodeError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    print(f"{version}+{build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
