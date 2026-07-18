from __future__ import annotations

import os
import platform
import re
import shlex
import shutil
import signal
import sqlite3
import struct
import subprocess
import sys
import time
import json
import threading
from contextlib import closing
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen

try:
    from invoke import task
    from invoke.exceptions import Exit
except ModuleNotFoundError:  # pragma: no cover - bootstrap fallback before dev deps are installed.

    class Exit(RuntimeError):
        pass

    def task(*args, **kwargs):
        if args and callable(args[0]) and len(args) == 1 and not kwargs:
            return args[0]

        def decorator(func):
            return func

        return decorator


ROOT = Path(__file__).resolve().parent
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000
DEFAULT_HEALTH_URL = f"http://{DEFAULT_HOST}:{DEFAULT_PORT}/health"
DEFAULT_PREVIEW_BASE_URL = "http://localhost:8000"
DEFAULT_BROWSER_SEED_PATH = "app/fixtures/review_seed_e2e.json"
DEFAULT_BROWSER_DATABASE_URL = "sqlite+aiosqlite:///./tmp-ui-e2e-invoke.db"
DEFAULT_BROWSER_BACKUP_DIRECTORY = "e2e-artifacts/backups"
DEFAULT_PRIVACY_EMAIL = "privacy@example.com"
DEFAULT_SUPPORT_EMAIL = "support@example.com"
DEFAULT_APP_LOG_PATH = "ui-e2e-server.log"
DEFAULT_APP_PID_PATH = "ui-e2e-server.pid"
DEFAULT_IOS_E2E_PORT = 8017
DEFAULT_IOS_E2E_BASE_URL = f"http://localhost:{DEFAULT_IOS_E2E_PORT}"
DEFAULT_IOS_E2E_DATABASE_URL = "sqlite+aiosqlite:///./tmp-ios-e2e.db"
DEFAULT_IOS_E2E_LOG_PATH = "ios-e2e-server.log"
DEFAULT_IOS_E2E_PID_PATH = "ios-e2e-server.pid"
DEFAULT_IOS_E2E_USER_EMAIL = "planini@schaedler.rocks"
DEFAULT_IOS_UI_E2E_PORT = 8018
DEFAULT_IOS_UI_E2E_BASE_URL = f"http://localhost:{DEFAULT_IOS_UI_E2E_PORT}"
DEFAULT_IOS_UI_E2E_DATABASE_URL = "sqlite+aiosqlite:///./tmp-ios-ui-e2e.db"
DEFAULT_IOS_UI_E2E_LOG_PATH = "ios-ui-e2e-server.log"
DEFAULT_IOS_UI_E2E_PID_PATH = "ios-ui-e2e-server.pid"
DEFAULT_IOS_UI_E2E_ARTIFACT_DIR = "e2e-artifacts/ios-ui-e2e"
DEFAULT_IOS_UI_E2E_RESULT_BUNDLE = "PlaniniUITests.xcresult"
DEFAULT_IOS_UI_E2E_DEVICE = "iPhone 17 Pro"
DEFAULT_IOS_UI_E2E_INITIAL_LIST = "Browser Test Shop"
DEFAULT_IOS_MARKETING_SCREENSHOT_PORT = 8019
DEFAULT_IOS_MARKETING_SCREENSHOT_DATABASE_URL = (
    "sqlite+aiosqlite:///./tmp-ios-marketing-screenshots.db"
)
DEFAULT_IOS_MARKETING_SCREENSHOT_LOG_PATH = "ios-marketing-screenshots-server.log"
DEFAULT_IOS_MARKETING_SCREENSHOT_PID_PATH = "ios-marketing-screenshots-server.pid"
DEFAULT_IOS_MARKETING_SCREENSHOT_ARTIFACT_DIR = "e2e-artifacts/ios-marketing-screenshots"
DEFAULT_IOS_MARKETING_SCREENSHOT_SEED_PATH = "app/fixtures/ios_marketing_seed.json"
DEFAULT_IOS_MARKETING_SCREENSHOT_DEVICE = "iPhone 14 Plus"
DEFAULT_IOS_MARKETING_SCREENSHOT_IPAD_DEVICE = "iPad Pro 13-inch (M5)"
DEFAULT_IOS_MARKETING_SCREENSHOT_WATCH_PHONE_DEVICE = "iPhone 17 Pro"
DEFAULT_IOS_MARKETING_SCREENSHOT_WATCH_DEVICE = "Apple Watch Ultra 3 (49mm)"
DEFAULT_IOS_MARKETING_SCREENSHOT_INITIAL_LIST = "Weekly groceries"
DEFAULT_IOS_MARKETING_SCREENSHOT_GERMAN_USER_EMAIL = "planini-de@schaedler.rocks"
DEFAULT_IOS_MARKETING_SCREENSHOT_GERMAN_INITIAL_LIST = "Wocheneinkauf"
DEFAULT_IOS_MARKETING_SCREENSHOT_TEST = "PlaniniUITests/PlaniniUITests/testMarketingScreenshots"
DEFAULT_IOS_MARKETING_SCREENSHOT_SIZE = (1284, 2778)
DEFAULT_IOS_MARKETING_SCREENSHOT_IPAD_SIZE = (2064, 2752)
DEFAULT_IOS_MARKETING_SCREENSHOT_WATCH_SIZE = (422, 514)
DEFAULT_IOS_SIMULATOR_DESTINATION = "generic/platform=iOS Simulator"
DEFAULT_IOS_APP_BACKEND_URL = "https://planini.malaber.de"
DEFAULT_IOS_APP_BUNDLE_IDENTIFIER = "de.malaber.planini"
DEFAULT_IOS_WATCH_APP_BUNDLE_IDENTIFIER = "de.malaber.planini.watchkitapp"
DEFAULT_IOS_APP_DEVELOPMENT_TEAM = "VWKG94374J"
DEFAULT_IOS_SIMULATOR_PHONE_DEVICE = "iPhone 17 Pro"
DEFAULT_IOS_SIMULATOR_WATCH_DEVICE = "Apple Watch Ultra 3 (49mm)"
IOS_PROJECT_YML_PATH = ROOT / "ios" / "PlaniniIOS" / "project.yml"
IOS_ENTITLEMENTS_PATH = ROOT / "ios" / "PlaniniIOS" / "App" / "Planini.entitlements"
IOS_GENERATED_CONFIG_PATH = (
    ROOT / "ios" / "PlaniniIOS" / "App" / "BuildConfiguration.generated.swift"
)
STABLE_TAG_PATTERN = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
IOS_APP_ICON_BACKGROUND_PATTERN = re.compile(
    r"(\.cls-1\s*\{\s*fill:\s*)#[0-9a-fA-F]{6}(\s*;)",
    re.MULTILINE,
)
IOS_DEFAULT_APP_ICON_BACKGROUND_COLOR = "#ddddc1"

IOS_APP_ICON_SOURCE_PATH = ROOT / "app" / "web" / "static" / "img" / "planini.svg"
IOS_APP_ICONSET_PATH = ROOT / "ios" / "PlaniniIOS" / "Assets.xcassets" / "AppIcon.appiconset"
IOS_WATCH_APP_ICONSET_PATH = (
    ROOT / "ios" / "PlaniniIOS" / "Assets.xcassets" / "WatchAppIcon.appiconset"
)
IOS_APP_ICON_FILES = {
    "Icon-20@2x.png": 40,
    "Icon-20@3x.png": 60,
    "Icon-29@2x.png": 58,
    "Icon-29@3x.png": 87,
    "Icon-40@2x.png": 80,
    "Icon-40@3x.png": 120,
    "Icon-60@2x.png": 120,
    "Icon-60@3x.png": 180,
    "Icon-iPad-20.png": 20,
    "Icon-iPad-20@2x.png": 40,
    "Icon-iPad-29.png": 29,
    "Icon-iPad-29@2x.png": 58,
    "Icon-iPad-40.png": 40,
    "Icon-iPad-40@2x.png": 80,
    "Icon-iPad-76.png": 76,
    "Icon-iPad-76@2x.png": 152,
    "Icon-iPad-83.5@2x.png": 167,
    "Icon-1024.png": 1024,
}
IOS_WATCH_APP_ICON_FILES = {
    "Icon-24@2x.png": 48,
    "Icon-27.5@2x.png": 55,
    "Icon-29@2x.png": 58,
    "Icon-29@3x.png": 87,
    "Icon-40@2x.png": 80,
    "Icon-44@2x.png": 88,
    "Icon-50x50@2x.png": 100,
    "Icon-86@2x.png": 172,
    "Icon-98@2x.png": 196,
    "Icon-108@2x.png": 216,
    "Icon-1024.png": 1024,
}


def _tool_path(name: str) -> str:
    current_bin = Path(sys.executable).resolve().parent / name
    if current_bin.exists():
        return str(current_bin)

    local_bin = ROOT / ".venv" / "bin" / name
    if local_bin.exists():
        return str(local_bin)

    return name


def _git_lines(*args: str) -> list[str]:
    return subprocess.run(
        ["git", *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()


def _python_env(**overrides: str) -> dict[str, str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = "."
    env.update({key: value for key, value in overrides.items() if value is not None})
    return env


def _pip_env() -> dict[str, str]:
    env = os.environ.copy()
    for var_name in ("SSL_CERT_FILE", "REQUESTS_CA_BUNDLE"):
        value = env.get(var_name)
        if value and not Path(value).exists():
            env.pop(var_name, None)
    return env


def _print_hidden_output(result) -> None:
    for stream_name in ("stdout", "stderr"):
        output = getattr(result, stream_name, "") or ""
        if output:
            print(output, end="" if output.endswith("\n") else "\n")


def _run_quiet(c, command: str, **kwargs):
    result = c.run(command, hide=True, warn=True, **kwargs)
    if result.exited != 0:
        _print_hidden_output(result)
        raise Exit(f"Command failed with exit code {result.exited}: {command}")
    return result


def _node_bootstrap() -> str:
    version_check = (
        "node -e \"process.exit(Number(process.versions.node.split('.')[0]) === 24 ? 0 : 1)\""
    )
    return (
        f"if {version_check}; then true; "
        'elif [ -s "$HOME/.nvm/nvm.sh" ]; then '
        'source "$HOME/.nvm/nvm.sh" && nvm use 24 >/dev/null; '
        "else "
        "echo 'Node 24.x is required. Run `nvm use 24` or equivalent first.' >&2; "
        "exit 1; "
        "fi && "
        f"{version_check}"
    )


def _node_command(command: str) -> str:
    return f"{_node_bootstrap()} && {command}"


def _black_command(*args: str) -> str:
    return " ".join([shlex.quote(_tool_path("black")), *args])


def _app_env(
    *,
    seed_path: str,
    database_url: str,
    webauthn_rp_id: str,
    ui_test_bootstrap_enabled: bool = False,
    app_base_url: str | None = None,
    webcredentials_apps: str | None = None,
    backup_directory: str | None = DEFAULT_BROWSER_BACKUP_DIRECTORY,
) -> dict[str, str]:
    return _python_env(
        SEED_DATA_PATH=seed_path,
        DATABASE_URL=database_url,
        BACKUP_DIRECTORY=backup_directory,
        APP_BASE_URL=app_base_url,
        WEBAUTHN_RP_ID=webauthn_rp_id,
        WEBCREDENTIALS_APPS=webcredentials_apps,
        UI_TEST_BOOTSTRAP_ENABLED="true" if ui_test_bootstrap_enabled else "false",
        PRIVACY_EMAIL=os.environ.get("PRIVACY_EMAIL", DEFAULT_PRIVACY_EMAIL),
        SUPPORT_EMAIL=os.environ.get("SUPPORT_EMAIL", DEFAULT_SUPPORT_EMAIL),
    )


def _ios_ui_test_env(
    *,
    base_url: str,
    bootstrap_base_url: str,
    user_email: str,
    artifact_dir: str,
    initial_list_name: str,
    language: str = "en",
    access_token: str | None = None,
    display_name: str | None = None,
) -> dict[str, str]:
    env = _ios_toolchain_env()
    env.update(
        {
            "PLANINI_UI_TEST_BASE_URL": base_url,
            "PLANINI_UI_TEST_BOOTSTRAP_BASE_URL": bootstrap_base_url,
            "PLANINI_UI_TEST_USER_EMAIL": user_email,
            "PLANINI_UI_TEST_ARTIFACT_DIR": str((ROOT / artifact_dir).resolve()),
            "PLANINI_UI_TEST_INITIAL_LIST_NAME": initial_list_name,
            "PLANINI_UI_TEST_LANGUAGE": language,
        }
    )
    if access_token:
        env["PLANINI_UI_TEST_ACCESS_TOKEN"] = access_token
    if display_name:
        env["PLANINI_UI_TEST_DISPLAY_NAME"] = display_name
    return env


def _write_ios_ui_e2e_summary(artifact_dir: str) -> None:
    artifact_path = ROOT / artifact_dir
    screenshots = sorted(path.name for path in artifact_path.glob("*.png"))
    result_bundle_path = artifact_path / DEFAULT_IOS_UI_E2E_RESULT_BUNDLE
    failure_summaries = _ios_ui_e2e_failure_summaries(result_bundle_path)
    summary_lines = [
        "# iOS UI e2e",
        "",
        f"Stored screenshots: {len(screenshots)}",
    ]
    if failure_summaries:
        summary_lines.extend(["", "## Failures"])
        summary_lines.extend(f"- {summary}" for summary in failure_summaries)
    if screenshots:
        summary_lines.extend(["", "## Screenshots"])
        summary_lines.extend(f"- {name}" for name in screenshots)
    if result_bundle_path.exists():
        summary_lines.extend(
            [
                "",
                "## Result Bundle",
                f"- {DEFAULT_IOS_UI_E2E_RESULT_BUNDLE}",
                "- XCTest screenshot attachments are preserved inside this bundle for CI download.",
            ]
        )
    (artifact_path / "summary.md").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")


def _dedupe_lines(lines: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for line in lines:
        normalized = " ".join(line.split())
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        deduped.append(normalized)
    return deduped


def _scalar_string(value: object) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, bool):
        return ""
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else str(value)
    if isinstance(value, dict):
        return _scalar_string(value.get("_value"))
    return ""


def _string_field(payload: dict[str, object], *keys: str) -> str:
    for key in keys:
        value = _scalar_string(payload.get(key))
        if value:
            return value
    return ""


def _xcresult_location_fragment(value: str) -> int | None:
    match = re.search(r"(?:StartingLineNumber|lineNumber|line)=(\d+)", value)
    if not match:
        return None
    return int(match.group(1))


def _xcresult_line_number(payload: dict[str, object]) -> int | None:
    for key in ("lineNumber", "line", "startingLineNumber"):
        value = _string_field(payload, key)
        if value.isdigit():
            return int(value)
    for key in ("fileName", "filePath", "fileURL", "url", "documentURL"):
        value = _string_field(payload, key)
        if value:
            line = _xcresult_location_fragment(value)
            if line is not None:
                return line
    return None


def _short_xcresult_path(path_value: str) -> str:
    parsed = urlparse(path_value)
    path = unquote(parsed.path) if parsed.scheme == "file" else path_value
    if not path:
        path = path_value
    path = path.split("#", 1)[0]
    try:
        path_obj = Path(path)
        if path_obj.is_absolute():
            try:
                return path_obj.relative_to(ROOT).as_posix()
            except ValueError:
                parts = path_obj.parts
                if "ios" in parts:
                    return "/".join(parts[parts.index("ios") :])
                return "/".join(parts[-3:])
        return path_obj.as_posix()
    except ValueError:
        return path


def _xcresult_location(payload: dict[str, object], inherited_location: str = "") -> str:
    for key in ("sourceCodeContext", "location", "documentLocationInCreatingWorkspace"):
        nested = payload.get(key)
        if isinstance(nested, dict):
            location = _xcresult_location(nested, inherited_location)
            if location:
                return location

    path = _string_field(payload, "fileName", "filePath", "fileURL", "url", "documentURL")
    line = _xcresult_line_number(payload)
    if not path:
        return inherited_location

    location = _short_xcresult_path(path)
    if line is not None:
        return f"{location}:{line}"
    return location or inherited_location


def _format_xcresult_failure_summary(
    *,
    test_name: str,
    message: str,
    location: str,
) -> str:
    label = test_name or "iOS UI test"
    context = f" ({location})" if location else ""
    return f"{label}{context}: {message}"


def _collect_xcresult_failure_summaries(
    payload: object, current_test: str = "", current_location: str = ""
) -> list[str]:
    if isinstance(payload, list):
        summaries: list[str] = []
        for item in payload:
            summaries.extend(
                _collect_xcresult_failure_summaries(item, current_test, current_location)
            )
        return summaries

    if not isinstance(payload, dict):
        return []

    test_name = (
        _string_field(
            payload,
            "testName",
            "name",
            "identifier",
            "displayName",
        )
        or current_test
    )
    status = _string_field(
        payload,
        "testStatus",
        "status",
        "result",
        "outcome",
    ).lower()
    message = _string_field(
        payload,
        "message",
        "failureMessage",
        "failureText",
        "detailedDescription",
        "compactDescription",
        "issueDescription",
        "reason",
        "errorMessage",
    )
    if not message and ("fail" in status or "error" in status):
        message = _string_field(payload, "summary", "description")
    location = _xcresult_location(payload, current_location)

    skipped_keys = {
        "testName",
        "name",
        "identifier",
        "displayName",
        "testStatus",
        "status",
        "result",
        "outcome",
        "message",
        "failureMessage",
        "failureText",
        "detailedDescription",
        "compactDescription",
        "issueDescription",
        "summary",
        "description",
        "reason",
        "errorMessage",
        "fileName",
        "filePath",
        "fileURL",
        "url",
        "documentURL",
        "lineNumber",
        "line",
        "startingLineNumber",
    }
    child_summaries: list[str] = []
    for key, value in payload.items():
        if key in skipped_keys:
            continue
        child_summaries.extend(_collect_xcresult_failure_summaries(value, test_name, location))

    summaries: list[str] = []
    if message and ("fail" in status or "error" in status or current_test or test_name):
        summaries.append(
            _format_xcresult_failure_summary(
                test_name=test_name,
                message=message,
                location=location,
            )
        )
    elif "fail" in status and test_name and not child_summaries:
        summaries.append(
            _format_xcresult_failure_summary(
                test_name=test_name,
                message="failed",
                location=location,
            )
        )
    summaries.extend(child_summaries)
    return _dedupe_lines(summaries)


def _xcresulttool_json(
    result_bundle_path: Path,
    subcommand: str,
    *,
    test_id: str = "",
) -> object | None:
    if result_bundle_path.exists() is False:
        return None

    command = [
        "xcrun",
        "xcresulttool",
        "get",
        "test-results",
        subcommand,
        "--path",
        str(result_bundle_path),
        "--compact",
    ]
    if test_id:
        command.extend(["--test-id", test_id])
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def _xcresult_failure_records(payload: object) -> list[tuple[str, str, str]]:
    if isinstance(payload, list):
        records: list[tuple[str, str, str]] = []
        for item in payload:
            records.extend(_xcresult_failure_records(item))
        return records
    if not isinstance(payload, dict):
        return []

    test_id = _string_field(payload, "testIdentifierURL", "testIdentifierString")
    test_name = _string_field(payload, "testName", "name")
    failure_text = _string_field(payload, "failureText", "failureMessage")
    records = [(test_name, failure_text, test_id)] if test_id and failure_text else []
    for value in payload.values():
        records.extend(_xcresult_failure_records(value))

    seen: set[tuple[str, str, str]] = set()
    deduped: list[tuple[str, str, str]] = []
    for record in records:
        if record in seen:
            continue
        seen.add(record)
        deduped.append(record)
    return deduped


def _collect_xcresult_failure_detail_context(payload: object) -> list[str]:
    if isinstance(payload, list):
        context: list[str] = []
        for item in payload:
            context.extend(_collect_xcresult_failure_detail_context(item))
        return _dedupe_lines(context)
    if not isinstance(payload, dict):
        return []

    labels = {
        "Source Code Reference": "Source",
        "Expression": "Expression",
        "Test Value": "Value",
    }
    node_type = _string_field(payload, "nodeType")
    values = _dedupe_lines(
        [
            _string_field(payload, "name"),
            _string_field(payload, "details"),
        ]
    )
    context = (
        [f"{labels[node_type]}: {' - '.join(values)}"] if node_type in labels and values else []
    )
    for value in payload.values():
        context.extend(_collect_xcresult_failure_detail_context(value))
    return _dedupe_lines(context)


def _collect_xcresult_failure_activity_context(
    payload: object,
    activity_path: tuple[str, ...] = (),
) -> list[str]:
    if isinstance(payload, list):
        context: list[str] = []
        for item in payload:
            context.extend(_collect_xcresult_failure_activity_context(item, activity_path))
        return _dedupe_lines(context)
    if not isinstance(payload, dict):
        return []

    title = _string_field(payload, "title")
    current_path = (*activity_path, title) if title else activity_path
    context = []
    if payload.get("isAssociatedWithFailure") is True and current_path:
        context.append(f"Failure activity: {' > '.join(current_path[-5:])}")
    for value in payload.values():
        context.extend(_collect_xcresult_failure_activity_context(value, current_path))
    return _dedupe_lines(context)


def _ios_ui_e2e_failure_summaries_from_xcresulttool(result_bundle_path: Path) -> list[str]:
    payload = _xcresulttool_json(result_bundle_path, "summary")
    if payload is None:
        return []

    summaries = _collect_xcresult_failure_summaries(payload)
    for test_name, failure_text, test_id in _xcresult_failure_records(payload):
        label = test_name or test_id
        summaries.append(f"{label}: {failure_text}")
        details = _xcresulttool_json(result_bundle_path, "test-details", test_id=test_id)
        if details is not None:
            summaries.extend(
                f"{label}: {context}"
                for context in _collect_xcresult_failure_detail_context(details)
            )
        activities = _xcresulttool_json(result_bundle_path, "activities", test_id=test_id)
        if activities is not None:
            summaries.extend(
                f"{label}: {context}"
                for context in _collect_xcresult_failure_activity_context(activities)
            )
    return _dedupe_lines(summaries)


def _ios_ui_e2e_failure_summaries(result_bundle_path: Path) -> list[str]:
    xcresulttool_summaries = _ios_ui_e2e_failure_summaries_from_xcresulttool(result_bundle_path)
    if xcresulttool_summaries:
        return xcresulttool_summaries

    database_path = result_bundle_path / "database.sqlite3"
    if database_path.exists() is False:
        return []

    query = """
        SELECT
            t.name,
            r.result,
            COALESCE(i.compactDescription, ''),
            COALESCE(i.detailedDescription, '')
        FROM TestCaseRuns r
        JOIN TestCases t ON t.rowid = r.testCase_fk
        LEFT JOIN TestIssues i ON i.testCaseRun_fk = r.rowid
        WHERE r.result != 'Success'
        ORDER BY t.name, i.orderInOwner
    """
    with closing(sqlite3.connect(database_path)) as connection:
        rows = connection.execute(query).fetchall()

    summaries: list[str] = []
    for test_name, result, compact_description, detailed_description in rows:
        message = detailed_description or compact_description or "No failure details recorded."
        summaries.append(f"{test_name} [{result}]: {message}")
    return summaries


def _ios_simulator_destination(device_name: str) -> str:
    destination_parts = [
        "platform=iOS Simulator",
        f"name={device_name}",
        "OS=latest",
    ]
    if platform.machine().lower() == "arm64":
        destination_parts.append("arch=arm64")
    return ",".join(destination_parts)


def _ensure_ios_simulator_device(device_name: str) -> None:
    env = _ios_toolchain_env()
    existing_udid = next(
        (
            udid
            for udid, device in _list_available_simulators(env).items()
            if device.get("name") == device_name
        ),
        None,
    )
    if existing_udid is not None:
        _boot_simulator(env, existing_udid)
        return

    device_types_payload = _simctl_json(env, "list", "devicetypes", "-j")
    device_types = device_types_payload.get("devicetypes", [])
    device_type_id = next(
        (
            device_type.get("identifier")
            for device_type in device_types
            if isinstance(device_type, dict) and device_type.get("name") == device_name
        ),
        None,
    )
    if not isinstance(device_type_id, str):
        raise Exit(f"iOS simulator device type is unavailable: {device_name}")

    _run_command(
        ["xcrun", "simctl", "create", device_name, device_type_id],
        env=env,
    )
    _boot_simulator(env, _find_simulator_udid(env, device_name))


def _png_dimensions(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise Exit(f"Invalid PNG screenshot: {path}")
    return struct.unpack(">II", header[16:24])


def _validate_ios_screenshot_sizes(
    artifact_dir: str,
    expected_size: tuple[int, int],
) -> None:
    screenshots = sorted((ROOT / artifact_dir).glob("*.png"))
    if not screenshots:
        raise Exit(f"No iOS screenshots found in {ROOT / artifact_dir}")

    invalid_sizes = [
        f"{path.name}: {width}x{height}"
        for path in screenshots
        for width, height in [_png_dimensions(path)]
        if (width, height) != expected_size
    ]
    if invalid_sizes:
        expected_width, expected_height = expected_size
        raise Exit(
            f"Expected iOS screenshots sized {expected_width}x{expected_height}; "
            f"found {', '.join(invalid_sizes)}"
        )


def _capture_watch_marketing_screenshot(
    c,
    *,
    base_url: str,
    bootstrap_email: str,
    initial_list_name: str,
    language: str,
    locale: str,
    artifact_dir: str,
    phone_device: str,
    watch_device: str,
) -> None:
    _ensure_ios_simulator_device(watch_device)
    run_ios_simulators_fresh.body(
        c,
        phone_device=phone_device,
        watch_device=watch_device,
        derived_data_path=f"ios/PlaniniIOS/.derived-marketing-watch-{language}",
        backend_url_override=base_url,
        bootstrap_email=bootstrap_email,
        initial_list_name=initial_list_name,
    )
    env = _ios_toolchain_env()
    watch_udid = _find_simulator_udid(env, watch_device)
    time.sleep(4)
    _terminate_if_running(env, watch_udid, DEFAULT_IOS_WATCH_APP_BUNDLE_IDENTIFIER)
    _run_command(
        [
            "xcrun",
            "simctl",
            "launch",
            watch_udid,
            DEFAULT_IOS_WATCH_APP_BUNDLE_IDENTIFIER,
            "-AppleLanguages",
            f"({language})",
            "-AppleLocale",
            locale.replace("-", "_"),
        ],
        env=env,
    )
    time.sleep(4)
    screenshot_dir = ROOT / artifact_dir
    screenshot_dir.mkdir(parents=True, exist_ok=True)
    screenshot_path = screenshot_dir / "app-store-watch-01-lists.png"
    _run_command(
        ["xcrun", "simctl", "io", watch_udid, "screenshot", str(screenshot_path)],
        env=env,
    )
    _validate_ios_screenshot_sizes(
        artifact_dir,
        DEFAULT_IOS_MARKETING_SCREENSHOT_WATCH_SIZE,
    )


def _bootstrap_ios_ui_test_session(*, base_url: str, user_email: str) -> dict[str, str]:
    request = Request(
        url=f"{base_url.rstrip('/')}/api/v1/auth/ui-test-bootstrap",
        data=json.dumps({"email": user_email}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise Exit(
            f"iOS UI bootstrap failed with HTTP {exc.code} from {request.full_url}: {detail}"
        ) from exc
    except URLError as exc:
        raise Exit(f"iOS UI bootstrap failed for {request.full_url}: {exc}") from exc

    access_token = payload.get("access_token")
    display_name = payload.get("display_name")
    if not access_token or not display_name:
        raise Exit(f"iOS UI bootstrap returned an incomplete payload from {request.full_url}")
    return {"access_token": access_token, "display_name": display_name}


def _wait_for_healthcheck(url: str, attempts: int, sleep_seconds: float) -> None:
    last_error = ""
    for _ in range(attempts):
        try:
            with urlopen(url, timeout=2) as response:
                if 200 <= response.status < 400:
                    return
                last_error = f"unexpected status {response.status}"
        except URLError as exc:
            last_error = str(exc)
        time.sleep(sleep_seconds)
    raise Exit(f"App never became healthy at {url}: {last_error}")


def _read_pid(pid_path: Path) -> int | None:
    if not pid_path.exists():
        return None
    contents = pid_path.read_text(encoding="utf-8").strip()
    return int(contents) if contents else None


def _pid_is_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _wait_for_pid_exit(pid: int, timeout_seconds: float = 10.0, sleep_seconds: float = 0.1) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            waited_pid, _status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            waited_pid = 0
        if waited_pid == pid:
            return
        if not _pid_is_running(pid):
            return
        time.sleep(sleep_seconds)
    raise Exit(f"Timed out waiting for pid {pid} to exit")


def _database_url_for_device(database_url: str, device: str) -> str:
    prefix = "sqlite+aiosqlite:///"
    if not database_url.startswith(prefix):
        return database_url
    database_path = database_url.removeprefix(prefix)
    root, extension = os.path.splitext(database_path)
    suffix = extension or ".db"
    return f"{prefix}{root}-{device}{suffix}"


def _reset_sqlite_database_file(database_url: str) -> None:
    prefix = "sqlite+aiosqlite:///"
    if not database_url.startswith(prefix):
        return
    database_path = Path(database_url.removeprefix(prefix))
    for extra_suffix in ("", "-shm", "-wal"):
        database_path.with_name(f"{database_path.name}{extra_suffix}").unlink(missing_ok=True)


def _run_browser_e2e_for_device(
    c,
    *,
    device: str,
    base_url: str,
    seed_path: str,
    database_url: str,
    webauthn_rp_id: str,
    host: str,
    port: int,
    artifact_root: str,
    log_path: str,
    pid_path: str,
) -> None:
    device_database_url = _database_url_for_device(database_url, device)
    _reset_sqlite_database_file(device_database_url)
    start_app(
        c,
        seed_path=seed_path,
        database_url=device_database_url,
        webauthn_rp_id=webauthn_rp_id,
        host=host,
        port=port,
        log_path=log_path,
        pid_path=pid_path,
    )
    try:
        wait_for_app(c, url=f"http://{host}:{port}/health")
        run_browser_e2e(
            c,
            preview_base_url=base_url,
            e2e_seed_path=seed_path,
            webauthn_rp_id=webauthn_rp_id,
            artifact_dir=f"{artifact_root}/ui-e2e-{device}",
            device=device,
        )
    finally:
        stop_app(c, pid_path=pid_path)


def _ios_e2e_env(
    *,
    base_url: str,
    e2e_seed_path: str,
    webauthn_rp_id: str,
    user_email: str,
    origin: str = "",
) -> dict[str, str]:
    package_dir = ROOT / "ios" / "PlaniniIOS"
    clang_module_cache = package_dir / ".clang-module-cache"
    clang_module_cache.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env.update(
        {
            "PLANINI_E2E_BASE_URL": base_url,
            "PLANINI_E2E_SEED_PATH": (
                str((ROOT / e2e_seed_path).resolve())
                if not os.path.isabs(e2e_seed_path)
                else e2e_seed_path
            ),
            "PLANINI_E2E_USER_EMAIL": user_email,
            "PLANINI_E2E_RP_ID": webauthn_rp_id,
            "PLANINI_E2E_ORIGIN": origin.strip(),
            "DEVELOPER_DIR": env.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"),
            "CLANG_MODULE_CACHE_PATH": env.get(
                "CLANG_MODULE_CACHE_PATH", str(clang_module_cache.resolve())
            ),
        }
    )
    return env


def _ios_toolchain_env() -> dict[str, str]:
    package_dir = ROOT / "ios" / "PlaniniIOS"
    clang_module_cache = package_dir / ".clang-module-cache"
    clang_module_cache.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env.update(
        {
            "DEVELOPER_DIR": env.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"),
            "CLANG_MODULE_CACHE_PATH": env.get(
                "CLANG_MODULE_CACHE_PATH", str(clang_module_cache.resolve())
            ),
        }
    )
    return env


def _validated_ios_backend_host(backend_url: str) -> str:
    parsed = urlparse(backend_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise Exit("configure-ios-app requires a valid http or https backend_url.")
    return parsed.hostname


def _simctl_json(env: dict[str, str], *args: str) -> dict[str, object]:
    result = subprocess.run(
        ["xcrun", "simctl", *args],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    return json.loads(result.stdout)


def _run_command(command: list[str], *, env: dict[str, str]) -> None:
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise Exit(
            f"Command failed with exit code {result.returncode}: {' '.join(command)}\n{detail}"
        )


def _list_available_simulators(env: dict[str, str]) -> dict[str, dict[str, object]]:
    payload = _simctl_json(env, "list", "devices", "available", "-j")
    devices: dict[str, dict[str, object]] = {}
    for runtime_devices in payload.get("devices", {}).values():
        if not isinstance(runtime_devices, list):
            continue
        for device in runtime_devices:
            if not isinstance(device, dict):
                continue
            udid = device.get("udid")
            if isinstance(udid, str):
                devices[udid] = device
    return devices


def _find_simulator_udid(env: dict[str, str], name: str) -> str:
    devices = _list_available_simulators(env)
    exact_matches = [
        udid
        for udid, device in devices.items()
        if device.get("name") == name and device.get("isAvailable", True)
    ]
    if exact_matches:
        booted = [udid for udid in exact_matches if devices[udid].get("state") == "Booted"]
        return booted[0] if booted else exact_matches[0]
    raise Exit(f"Could not find an available simulator named {name!r}.")


def _phone_name_matches_pair(phone_name: str, requested_name: str) -> bool:
    normalized_phone_name = phone_name.strip()
    normalized_requested_name = requested_name.strip()
    return normalized_phone_name == normalized_requested_name or normalized_phone_name == (
        f"{normalized_requested_name} & Watch"
    )


def _find_simulator_pair(
    env: dict[str, str],
    phone_name: str,
    watch_name: str,
) -> tuple[str, str] | None:
    payload = _simctl_json(env, "list", "pairs", "-j")
    devices = _list_available_simulators(env)
    matching_pairs: list[tuple[str, str, bool]] = []
    for pair in payload.get("pairs", {}).values():
        if not isinstance(pair, dict):
            continue
        phone = pair.get("phone")
        watch = pair.get("watch")
        if not isinstance(phone, dict) or not isinstance(watch, dict):
            continue
        phone_udid = phone.get("udid")
        watch_udid = watch.get("udid")
        if not isinstance(phone_udid, str) or not isinstance(watch_udid, str):
            continue
        phone_device = devices.get(phone_udid)
        watch_device = devices.get(watch_udid)
        if not isinstance(phone_device, dict) or not isinstance(watch_device, dict):
            continue
        resolved_phone_name = str(phone_device.get("name", ""))
        resolved_watch_name = str(watch_device.get("name", ""))
        if not _phone_name_matches_pair(resolved_phone_name, phone_name):
            continue
        if resolved_watch_name != watch_name:
            continue
        either_booted = (
            phone_device.get("state") == "Booted" or watch_device.get("state") == "Booted"
        )
        matching_pairs.append((phone_udid, watch_udid, either_booted))

    if not matching_pairs:
        return None

    booted_pairs = [pair for pair in matching_pairs if pair[2]]
    selected_pair = booted_pairs[0] if booted_pairs else matching_pairs[0]
    return (selected_pair[0], selected_pair[1])


def _find_paired_watch_udid(env: dict[str, str], phone_udid: str, fallback_watch_name: str) -> str:
    payload = _simctl_json(env, "list", "pairs", "-j")
    devices = _list_available_simulators(env)
    for pair in payload.get("pairs", {}).values():
        if not isinstance(pair, dict):
            continue
        phone = pair.get("phone")
        watch = pair.get("watch")
        if not isinstance(phone, dict) or not isinstance(watch, dict):
            continue
        if phone.get("udid") != phone_udid:
            continue
        watch_udid = watch.get("udid")
        if isinstance(watch_udid, str) and watch_udid in devices:
            return watch_udid
    return _find_simulator_udid(env, fallback_watch_name)


def _boot_simulator(env: dict[str, str], udid: str) -> None:
    subprocess.run(
        ["xcrun", "simctl", "boot", udid],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    _run_command(["xcrun", "simctl", "bootstatus", udid, "-b"], env=env)


def _shutdown_ios_simulators() -> None:
    subprocess.run(
        ["xcrun", "simctl", "shutdown", "all"],
        env=_ios_toolchain_env(),
        capture_output=True,
        text=True,
        check=False,
    )


def _terminate_if_running(env: dict[str, str], udid: str, bundle_id: str) -> None:
    subprocess.run(
        ["xcrun", "simctl", "terminate", udid, bundle_id],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _uninstall_if_present(env: dict[str, str], udid: str, bundle_id: str) -> None:
    subprocess.run(
        ["xcrun", "simctl", "uninstall", udid, bundle_id],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _build_ios_product_paths(derived_data_path: Path, configuration: str) -> tuple[Path, Path]:
    ios_app_path = (
        derived_data_path
        / "Build"
        / "Products"
        / f"{configuration}-iphonesimulator"
        / "Planini.app"
    )
    watch_app_path = (
        derived_data_path
        / "Build"
        / "Products"
        / f"{configuration}-watchsimulator"
        / "Planini Watch.app"
    )
    return ios_app_path, watch_app_path


def _stream_process_output(process: subprocess.Popen[str], prefix: str) -> None:
    assert process.stdout is not None
    for line in process.stdout:
        print(f"[{prefix}] {line}", end="")


def _replace_project_setting(contents: str, key: str, value: str) -> str:
    pattern = re.compile(rf"^(\s*{re.escape(key)}:\s*).*$", re.MULTILINE)
    replacement = rf"\1{value}"
    if pattern.search(contents):
        return pattern.sub(replacement, contents, count=1)
    raise Exit(f"Could not find {key} in {IOS_PROJECT_YML_PATH}.")


def _write_ios_entitlements(host: str) -> None:
    # Native Apple passkeys only work when the signed app declares the same
    # webcredentials host that the backend advertises in its AASA file.
    IOS_ENTITLEMENTS_PATH.write_text(
        "\n".join(
            [
                '<?xml version="1.0" encoding="UTF-8"?>',
                '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
                '<plist version="1.0">',
                "<dict>",
                "\t<key>com.apple.security.application-groups</key>",
                "\t<array>",
                "\t\t<string>group.de.malaber.planini.watch</string>",
                "\t</array>",
                "\t<key>com.apple.developer.associated-domains</key>",
                "\t<array>",
                f"\t\t<string>applinks:{host}</string>",
                f"\t\t<string>webcredentials:{host}</string>",
                "\t</array>",
                "</dict>",
                "</plist>",
                "",
            ]
        ),
        encoding="utf-8",
    )


def _write_ios_generated_config(backend_url: str) -> None:
    IOS_GENERATED_CONFIG_PATH.write_text(
        "\n".join(
            [
                "import Foundation",
                "",
                "enum GeneratedBuildConfiguration {",
                f'    static let backendURL = "{backend_url}"',
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def _latest_stable_version_from_tags(tags: list[str]) -> str:
    versions = [
        tuple(map(int, match.groups()))
        for tag in tags
        if (match := STABLE_TAG_PATTERN.fullmatch(tag))
    ]
    if not versions:
        return "0.1.0"
    major, minor, patch = max(versions)
    return f"{major}.{minor}.{patch}"


def _next_stable_version(version: str, tags: list[str]) -> str:
    major, minor, patch = map(int, version.split("."))
    existing_tags = set(tags)
    while True:
        patch += 1
        candidate = f"{major}.{minor}.{patch}"
        if f"v{candidate}" not in existing_tags:
            return candidate


def _next_rc_version(version: str, run_number: int, tags: list[str]) -> str:
    rc_number = run_number
    existing_tags = set(tags)
    while True:
        candidate = f"{version}-rc.{rc_number}"
        if f"v{candidate}" not in existing_tags:
            return candidate
        rc_number += 1


def _compute_version_values(ref_name: str, run_number: int, tags: list[str]) -> dict[str, str]:
    base_version = _next_stable_version(_latest_stable_version_from_tags(tags), tags)
    if ref_name == "main":
        release_version = base_version
    else:
        release_version = _next_rc_version(base_version, run_number, tags)
    return {
        "base_version": base_version,
        "release_version": release_version,
        "git_tag": f"v{release_version}",
    }


def _write_github_output(values: dict[str, str]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with Path(output_path).open("a", encoding="utf-8") as fh:
            for key, value in values.items():
                fh.write(f"{key}={value}\n")
        return

    for key, value in values.items():
        print(f"{key}={value}")


def _normalize_ios_app_icon_background_color(background_color: str) -> str:
    color = background_color.strip().lower()
    if not re.fullmatch(r"#[0-9a-f]{6}", color):
        raise Exit("iOS app icon background color must be a #rrggbb hex color.")
    return color


def _ios_app_icon_svg_with_background_color(background_color: str) -> str:
    color = _normalize_ios_app_icon_background_color(background_color)
    svg = IOS_APP_ICON_SOURCE_PATH.read_text(encoding="utf-8")
    svg, replacements = IOS_APP_ICON_BACKGROUND_PATTERN.subn(rf"\g<1>{color}\g<2>", svg, count=1)
    if replacements != 1:
        raise Exit("Could not find .cls-1 fill color in iOS app icon source SVG.")
    return svg


@task(
    help={
        "background_color": (
            "Hex color for the SVG .cls-1 app icon background fill. Defaults to "
            "the release-candidate icon color."
        ),
    }
)
def generate_ios_app_icons(c, background_color=IOS_DEFAULT_APP_ICON_BACKGROUND_COLOR) -> None:
    """Generate ignored iOS AppIcon PNGs from the tracked Planini SVG."""

    try:
        import cairosvg
    except ModuleNotFoundError as exc:
        raise Exit("Missing cairosvg. Run `.venv/bin/inv install-deps` first.") from exc

    if not IOS_APP_ICON_SOURCE_PATH.exists():
        raise Exit(f"Missing app icon source SVG: {IOS_APP_ICON_SOURCE_PATH}")

    svg = _ios_app_icon_svg_with_background_color(background_color)
    iconsets = {
        IOS_APP_ICONSET_PATH: IOS_APP_ICON_FILES,
        IOS_WATCH_APP_ICONSET_PATH: IOS_WATCH_APP_ICON_FILES,
    }

    for iconset_path, icon_files in iconsets.items():
        iconset_path.mkdir(parents=True, exist_ok=True)
        for filename, size in icon_files.items():
            output_path = iconset_path / filename
            cairosvg.svg2png(
                bytestring=svg.encode("utf-8"),
                write_to=str(output_path),
                output_width=size,
                output_height=size,
            )
            print(f"Generated {output_path.relative_to(ROOT)} ({size}x{size})")


@task
def check_ios_app_icons(c) -> None:
    """Fail if generated iOS AppIcon PNGs are missing locally."""

    iconsets = {
        IOS_APP_ICONSET_PATH: IOS_APP_ICON_FILES,
        IOS_WATCH_APP_ICONSET_PATH: IOS_WATCH_APP_ICON_FILES,
    }
    missing = [
        iconset_path / filename
        for iconset_path, icon_files in iconsets.items()
        for filename in icon_files
        if not (iconset_path / filename).exists()
    ]

    if missing:
        missing_lines = "\n".join(f"- {path.relative_to(ROOT)}" for path in missing)
        raise Exit(
            "Missing generated iOS app icon PNGs:\n"
            f"{missing_lines}\n\n"
            "Run:\n"
            ".venv/bin/inv generate-ios-app-icons"
        )


@task
def setup(c) -> None:
    c.run("./.codex/setup.sh", pty=False, shell="/bin/bash")


@task(pre=[setup])
def bootstrap_ci(c) -> None:
    """Install the shared Python tooling CI tasks depend on."""


@task(
    help={
        "ref_name": "Git ref name used to decide stable vs rc versioning.",
        "run_number": "Run number used to derive rc suffixes on non-main refs.",
    }
)
def compute_version(c, ref_name="", run_number="") -> None:
    resolved_ref_name = ref_name or os.environ.get("REF_NAME") or os.environ.get("GITHUB_REF_NAME")
    resolved_run_number = (
        str(run_number)
        if run_number
        else (os.environ.get("RUN_NUMBER") or os.environ.get("GITHUB_RUN_NUMBER"))
    )
    if not resolved_ref_name:
        raise Exit("compute-version requires ref_name or REF_NAME/GITHUB_REF_NAME.")
    if not resolved_run_number:
        raise Exit("compute-version requires run_number or RUN_NUMBER/GITHUB_RUN_NUMBER.")

    tags = _git_lines("tag", "--list", "v*")
    values = _compute_version_values(
        ref_name=resolved_ref_name,
        run_number=int(resolved_run_number),
        tags=tags,
    )
    _write_github_output(values)


@task(help={"python_bin": "Python executable to use when creating the repo virtualenv."})
def setup_venv(c, python_bin="python3.14") -> None:
    venv_dir = ROOT / ".venv"
    if not venv_dir.exists():
        _run_quiet(c, f"{shlex.quote(python_bin)} -m venv .venv", pty=False, shell="/bin/bash")

    pip_path = ROOT / ".venv" / "bin" / "pip"
    _run_quiet(
        c,
        f"{shlex.quote(str(pip_path))} install -e '.[dev]'",
        env=_pip_env(),
        pty=False,
        shell="/bin/bash",
    )


@task(
    help={
        "python_bin": "Python executable to use when creating the repo virtualenv.",
        "with_browser": "Also install Playwright's Chromium browser bundle.",
        "browser_with_deps": "Use Playwright's --with-deps flow when installing the browser.",
    }
)
def install_deps(c, python_bin="python3.14", with_browser=False, browser_with_deps=False) -> None:
    setup_venv.body(c, python_bin=python_bin)
    install_js.body(c)
    if with_browser:
        install_browser.body(c, with_deps=browser_with_deps)


@task
def black_check(c) -> None:
    c.run(_black_command("--check", "."), env=_python_env(), pty=False)


@task
def flake8_check(c) -> None:
    c.run(f"{shlex.quote(_tool_path('flake8'))} .", env=_python_env(), pty=False)


@task
def test_python(c) -> None:
    c.run(f"{shlex.quote(_tool_path('pytest'))} -q", env=_python_env(), pty=False)


@task
def format_python(c) -> None:
    c.run(_black_command("."), env=_python_env(), pty=False)


@task(pre=[black_check, flake8_check])
def lint_python(c) -> None:
    """Run the Python formatter and linter checks."""


@task(pre=[lint_python, test_python])
def check_python(c) -> None:
    """Run the Python lint and test checks."""


@task
def install_js(c) -> None:
    _run_quiet(c, _node_command("npm ci"), pty=False, shell="/bin/bash")


@task
def check_js(c) -> None:
    c.run(_node_command("npm run --silent test:js"), pty=False, shell="/bin/bash")


@task(
    help={
        "source": "Source SVG used to render web icon PNG files.",
        "output_dir": "Directory that receives generated PNG web icons.",
    }
)
def generate_web_icons(
    c,
    source="app/web/static/img/planini.svg",
    output_dir="app/web/static/img",
) -> None:
    script_path = ROOT / "scripts" / "generate_web_icons.py"
    command = " ".join(
        [
            shlex.quote(_tool_path("python")),
            shlex.quote(str(script_path)),
            "--source",
            shlex.quote(source),
            "--output-dir",
            shlex.quote(output_dir),
        ]
    )
    c.run(command, env=_python_env(), pty=False, shell="/bin/bash")


@task(help={"with_deps": "Use Playwright's system dependency install flow."})
def install_browser(c, with_deps=False) -> None:
    playwright_install = "npx playwright install chromium"
    if with_deps:
        playwright_install = "npx playwright install --with-deps chromium"

    _run_quiet(c, _node_command(playwright_install), pty=False, shell="/bin/bash")


@task(help={"database_url": "SQLite database URL used by the browser e2e flow."})
def clean_browser_e2e(c, database_url=DEFAULT_BROWSER_DATABASE_URL) -> None:
    """Remove the generated browser e2e SQLite database and sidecar files."""
    _reset_sqlite_database_file(database_url)


@task(
    help={
        "seed_path": "Fixture used to seed the local app database.",
        "database_url": "Database URL for the temporary local app.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the browser.",
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
    }
)
def start_app(
    c,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_BROWSER_DATABASE_URL,
    webauthn_rp_id="localhost",
    host=DEFAULT_HOST,
    port=DEFAULT_PORT,
    log_path=DEFAULT_APP_LOG_PATH,
    pid_path=DEFAULT_APP_PID_PATH,
    ui_test_bootstrap_enabled=False,
    backup_directory=DEFAULT_BROWSER_BACKUP_DIRECTORY,
) -> None:
    pid_file = ROOT / pid_path
    existing_pid = _read_pid(pid_file)
    if existing_pid is not None:
        if _pid_is_running(existing_pid):
            raise Exit(f"Refusing to start a second app instance while {pid_path} already exists.")
        pid_file.unlink(missing_ok=True)

    log_file = ROOT / log_path
    log_file.parent.mkdir(parents=True, exist_ok=True)
    env = _app_env(
        seed_path=seed_path,
        database_url=database_url,
        webauthn_rp_id=webauthn_rp_id,
        ui_test_bootstrap_enabled=str(ui_test_bootstrap_enabled).lower() in {"1", "true", "yes"},
        app_base_url=f"http://localhost:{port}" if ui_test_bootstrap_enabled else None,
        webcredentials_apps="[]" if ui_test_bootstrap_enabled else None,
        backup_directory=backup_directory,
    )
    with log_file.open("w", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            [
                _tool_path("uvicorn"),
                "app.main:app",
                "--host",
                host,
                "--port",
                str(port),
            ],
            cwd=ROOT,
            env=env,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    pid_file.write_text(f"{process.pid}\n", encoding="utf-8")


@task(help={"pid_path": "PID file created by start-app."})
def stop_app(c, pid_path=DEFAULT_APP_PID_PATH) -> None:
    pid_file = ROOT / pid_path
    pid = _read_pid(pid_file)
    if pid is None:
        return

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    else:
        try:
            _wait_for_pid_exit(pid)
        except Exit:
            os.kill(pid, signal.SIGKILL)
            _wait_for_pid_exit(pid, timeout_seconds=5.0)
    finally:
        pid_file.unlink(missing_ok=True)


@task(
    help={
        "url": "Healthcheck URL to poll before running browser checks.",
        "attempts": "Number of healthcheck polls before failing.",
        "sleep_seconds": "Delay between healthcheck polls.",
    }
)
def wait_for_app(c, url=DEFAULT_HEALTH_URL, attempts=30, sleep_seconds=1.0) -> None:
    _wait_for_healthcheck(url=url, attempts=int(attempts), sleep_seconds=float(sleep_seconds))


@task(
    help={
        "preview_base_url": "Browser-facing base URL used by the Playwright flow.",
        "e2e_seed_path": "Fixture that contains passkey data for the browser flow.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the browser.",
        "artifact_dir": "Artifact directory used by the Playwright flow.",
        "device": "Playwright device name for the browser flow.",
    }
)
def run_browser_e2e(
    c,
    preview_base_url=DEFAULT_PREVIEW_BASE_URL,
    e2e_seed_path=DEFAULT_BROWSER_SEED_PATH,
    webauthn_rp_id="localhost",
    artifact_dir="e2e-artifacts/ui-e2e-desktop",
    device="desktop",
) -> None:
    env = os.environ.copy()
    env.update(
        {
            "PREVIEW_BASE_URL": preview_base_url,
            "E2E_SEED_PATH": e2e_seed_path,
            "WEBAUTHN_RP_ID": webauthn_rp_id,
            "PREVIEW_ARTIFACT_DIR": artifact_dir,
            "PREVIEW_BACKUP_DIR": DEFAULT_BROWSER_BACKUP_DIRECTORY,
            "PRIVACY_EMAIL": os.environ.get("PRIVACY_EMAIL", DEFAULT_PRIVACY_EMAIL),
            "SUPPORT_EMAIL": os.environ.get("SUPPORT_EMAIL", DEFAULT_SUPPORT_EMAIL),
        }
    )
    if device != "desktop":
        env["E2E_DEVICE"] = device
    c.run(_node_command("node scripts/run_ui_e2e.mjs"), env=env, pty=False, shell="/bin/bash")


@task(
    help={
        "package_path": "Swift package path for the reusable iOS core.",
    }
)
def check_ios_package(c, package_path="ios/PlaniniIOS") -> None:
    env = _ios_toolchain_env()
    c.run(
        f"xcrun swift test --package-path {shlex.quote(package_path)} --enable-code-coverage",
        env=env,
        pty=False,
        shell="/bin/bash",
    )


@task
def install_xcodegen(c) -> None:
    c.run(
        "brew list xcodegen >/dev/null 2>&1 || brew install xcodegen",
        pty=False,
        shell="/bin/bash",
    )


@task(
    help={
        "backend_url": (
            "Build-time backend URL embedded into the native app and used for "
            "webcredentials:<host>."
        ),
        "passkey_domain": (
            "Optional Associated Domains host for native passkeys. Defaults to "
            "the backend host, but can be a shared parent domain such as "
            "pr.planini.malaber.de."
        ),
        "bundle_id": (
            "Bundle identifier used for the native app build; the final Apple "
            "appID is TEAM_ID.bundle_id."
        ),
        "development_team": (
            "Apple Developer team ID to stamp into the generated Xcode project. "
            "Defaults to the repo's current shipping team."
        ),
        "regenerate_project": "Regenerate the Xcode project after updating the config.",
    }
)
def configure_ios_app(
    c,
    backend_url=DEFAULT_IOS_APP_BACKEND_URL,
    passkey_domain="",
    bundle_id=DEFAULT_IOS_APP_BUNDLE_IDENTIFIER,
    development_team=DEFAULT_IOS_APP_DEVELOPMENT_TEAM,
    regenerate_project=True,
) -> None:
    # Keep the embedded backend URL and associated domain aligned so self-hosted
    # builders can stamp one consistent passkey configuration into the app.
    host = _validated_ios_backend_host(backend_url)
    passkey_host = passkey_domain.strip() or host
    project_yml = IOS_PROJECT_YML_PATH.read_text(encoding="utf-8")
    project_yml = _replace_project_setting(
        project_yml,
        "PRODUCT_BUNDLE_IDENTIFIER",
        bundle_id,
    )
    project_yml = _replace_project_setting(
        project_yml,
        "DEVELOPMENT_TEAM",
        development_team,
    )
    project_yml = _replace_project_setting(
        project_yml,
        "INFOPLIST_KEY_PlaniniBackendBaseURL",
        backend_url,
    )
    IOS_PROJECT_YML_PATH.write_text(project_yml, encoding="utf-8")
    _write_ios_entitlements(passkey_host)
    _write_ios_generated_config(backend_url)
    if str(regenerate_project).lower() not in {"0", "false", "no"}:
        install_xcodegen.body(c)
        generate_ios_project.body(c)


@task(
    help={
        "project_dir": "Directory that contains the iOS XcodeGen project spec.",
    },
    pre=[generate_ios_app_icons],
)
def generate_ios_project(c, project_dir="ios/PlaniniIOS") -> None:
    c.run(
        f"cd {shlex.quote(project_dir)} && xcodegen generate",
        pty=False,
        shell="/bin/bash",
    )


@task(
    help={
        "project_dir": "Directory that contains the generated iOS Xcode project.",
        "scheme": "Xcode scheme to build.",
        "configuration": "Xcode build configuration to use.",
        "destination": "Xcode destination used for the simulator build.",
    }
)
def build_ios_simulator(
    c,
    project_dir="ios/PlaniniIOS",
    scheme="Planini",
    configuration="Debug",
    destination=DEFAULT_IOS_SIMULATOR_DESTINATION,
) -> None:
    env = _ios_toolchain_env()
    c.run(
        " ".join(
            [
                f"cd {shlex.quote(project_dir)} &&",
                "xcodebuild",
                "-project PlaniniApp.xcodeproj",
                f"-scheme {shlex.quote(scheme)}",
                f"-configuration {shlex.quote(configuration)}",
                f"-destination {shlex.quote(destination)}",
                "-quiet",
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ]
        ),
        env=env,
        pty=False,
        shell="/bin/bash",
    )


@task(
    help={
        "project_dir": "Directory that contains the generated iOS Xcode project.",
        "scheme": "Xcode scheme to build and launch.",
        "configuration": "Xcode build configuration to use.",
        "phone_device": "Paired iPhone simulator name to boot, install, and launch on.",
        "watch_device": "Paired Apple Watch simulator name to boot, install, and launch on.",
        "phone_udid": "Exact iPhone simulator UDID to use instead of name-based resolution.",
        "watch_udid": "Exact Apple Watch simulator UDID to use instead of name-based resolution.",
        "derived_data_path": "Derived data folder used for the clean rebuild.",
        "backend_url_override": "Runtime backend URL override passed to the iPhone app at launch.",
        "bootstrap_email": "Seeded email used for simulator bootstrap login at launch.",
        "initial_list_name": "Optional seeded list name the simulator app should open first.",
    }
)
def run_ios_simulators_fresh(
    c,
    project_dir="ios/PlaniniIOS",
    scheme="Planini",
    configuration="Debug",
    phone_device=DEFAULT_IOS_SIMULATOR_PHONE_DEVICE,
    watch_device=DEFAULT_IOS_SIMULATOR_WATCH_DEVICE,
    phone_udid="",
    watch_udid="",
    derived_data_path="ios/PlaniniIOS/.derived-run-fresh",
    backend_url_override="http://localhost:8000",
    bootstrap_email=DEFAULT_IOS_E2E_USER_EMAIL,
    initial_list_name=DEFAULT_IOS_UI_E2E_INITIAL_LIST,
) -> None:
    env = _ios_toolchain_env()
    print(f"[run-ios-simulators-fresh] Resolving simulators: {phone_device} + {watch_device}")
    if phone_udid.strip() and watch_udid.strip():
        phone_udid = phone_udid.strip()
        watch_udid = watch_udid.strip()
    else:
        paired_devices = _find_simulator_pair(env, phone_device, watch_device)
        if paired_devices is not None:
            phone_udid, watch_udid = paired_devices
        else:
            phone_udid = _find_simulator_udid(env, phone_device)
            watch_udid = _find_paired_watch_udid(env, phone_udid, watch_device)
    print(f"[run-ios-simulators-fresh] Using iPhone simulator {phone_udid}")
    print(f"[run-ios-simulators-fresh] Using Watch simulator {watch_udid}")

    print("[run-ios-simulators-fresh] Booting simulators...")
    _boot_simulator(env, phone_udid)
    _boot_simulator(env, watch_udid)

    subprocess.run(
        ["open", "-a", "Simulator"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    phone_bundle_id = DEFAULT_IOS_APP_BUNDLE_IDENTIFIER
    watch_bundle_id = DEFAULT_IOS_WATCH_APP_BUNDLE_IDENTIFIER

    print("[run-ios-simulators-fresh] Removing previously installed app copies...")
    _terminate_if_running(env, phone_udid, phone_bundle_id)
    _terminate_if_running(env, watch_udid, watch_bundle_id)
    _uninstall_if_present(env, phone_udid, phone_bundle_id)
    _uninstall_if_present(env, watch_udid, watch_bundle_id)

    derived_data = ROOT / derived_data_path
    print(f"[run-ios-simulators-fresh] Clearing derived data at {derived_data}")
    shutil.rmtree(derived_data, ignore_errors=True)

    print("[run-ios-simulators-fresh] Building iPhone and Watch apps from scratch...")
    command = " ".join(
        [
            f"cd {shlex.quote(project_dir)} &&",
            "xcodebuild",
            "-project PlaniniApp.xcodeproj",
            f"-scheme {shlex.quote(scheme)}",
            f"-configuration {shlex.quote(configuration)}",
            f"-derivedDataPath {shlex.quote(str(derived_data.resolve()))}",
            f"-destination {shlex.quote(DEFAULT_IOS_SIMULATOR_DESTINATION)}",
            "-quiet",
            "CODE_SIGNING_ALLOWED=NO",
            "clean",
            "build",
        ]
    )
    c.run(
        command,
        env=env,
        pty=False,
        shell="/bin/bash",
    )

    ios_app_path, watch_app_path = _build_ios_product_paths(derived_data, configuration)
    if ios_app_path.exists() is False:
        raise Exit(f"Built iPhone app not found at {ios_app_path}")
    if watch_app_path.exists() is False:
        raise Exit(f"Built watch app not found at {watch_app_path}")

    print(f"[run-ios-simulators-fresh] Installing iPhone app from {ios_app_path}")
    _run_command(["xcrun", "simctl", "install", phone_udid, str(ios_app_path)], env=env)
    print(f"[run-ios-simulators-fresh] Installing Watch app from {watch_app_path}")
    _run_command(["xcrun", "simctl", "install", watch_udid, str(watch_app_path)], env=env)

    launch_env = env.copy()
    if backend_url_override.strip():
        launch_env["SIMCTL_CHILD_PLANINI_BACKEND_BASE_URL_OVERRIDE"] = backend_url_override.strip()
    if bootstrap_email.strip():
        launch_env["SIMCTL_CHILD_PLANINI_SIMULATOR_BOOTSTRAP_EMAIL"] = bootstrap_email.strip()
    if initial_list_name.strip():
        launch_env["SIMCTL_CHILD_PLANINI_SIMULATOR_INITIAL_LIST_NAME"] = initial_list_name.strip()

    print(
        "[run-ios-simulators-fresh] Launching iPhone app with backend override "
        f"{backend_url_override}"
    )
    _run_command(["xcrun", "simctl", "launch", phone_udid, phone_bundle_id], env=launch_env)
    time.sleep(2)
    print("[run-ios-simulators-fresh] Launching Watch app")
    _run_command(["xcrun", "simctl", "launch", watch_udid, watch_bundle_id], env=env)
    print("[run-ios-simulators-fresh] Done.")


@task(
    help={
        "phone_device": "iPhone simulator name used to resolve the paired watch.",
        "watch_device": "Apple Watch simulator name used to resolve the watch device.",
        "phone_udid": "Exact iPhone simulator UDID to use instead of name-based resolution.",
        "watch_udid": "Exact Apple Watch simulator UDID to use instead of name-based resolution.",
    }
)
def stream_ios_simulator_logs(
    c,
    phone_device=DEFAULT_IOS_SIMULATOR_PHONE_DEVICE,
    watch_device=DEFAULT_IOS_SIMULATOR_WATCH_DEVICE,
    phone_udid="",
    watch_udid="",
) -> None:
    env = _ios_toolchain_env()
    if phone_udid.strip() and watch_udid.strip():
        phone_udid = phone_udid.strip()
        watch_udid = watch_udid.strip()
    else:
        paired_devices = _find_simulator_pair(env, phone_device, watch_device)
        if paired_devices is not None:
            phone_udid, watch_udid = paired_devices
        else:
            phone_udid = _find_simulator_udid(env, phone_device)
            watch_udid = _find_paired_watch_udid(env, phone_udid, watch_device)
    print(f"[stream-ios-simulator-logs] iPhone simulator: {phone_udid}")
    print(f"[stream-ios-simulator-logs] Watch simulator: {watch_udid}")
    print("[stream-ios-simulator-logs] Streaming Planini app and watch logs. Press Ctrl+C to stop.")

    predicate = (
        'subsystem == "de.malaber.planini.watch" OR '
        'subsystem == "de.malaber.planini.ios" OR '
        'process == "Planini" OR '
        'process == "Planini Watch" OR '
        'process == "Planini Watch Extension"'
    )
    phone_process = subprocess.Popen(
        [
            "xcrun",
            "simctl",
            "spawn",
            phone_udid,
            "log",
            "stream",
            "--style",
            "compact",
            "--predicate",
            predicate,
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    watch_process = subprocess.Popen(
        [
            "xcrun",
            "simctl",
            "spawn",
            watch_udid,
            "log",
            "stream",
            "--style",
            "compact",
            "--predicate",
            predicate,
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    phone_thread = threading.Thread(
        target=_stream_process_output,
        args=(phone_process, "iphone"),
        daemon=True,
    )
    watch_thread = threading.Thread(
        target=_stream_process_output,
        args=(watch_process, "watch"),
        daemon=True,
    )
    phone_thread.start()
    watch_thread.start()

    try:
        phone_process.wait()
        watch_process.wait()
    except KeyboardInterrupt:
        phone_process.terminate()
        watch_process.terminate()
        raise


@task(
    help={
        "base_url": "Base URL used by the native iOS backend e2e flow.",
        "e2e_seed_path": "Fixture that contains passkey data for the native iOS flow.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the native iOS flow.",
        "user_email": "Seeded user email used for the native iOS passkey login.",
        "origin": (
            "Optional origin embedded into the seeded passkey assertion. Defaults to "
            "the base_url origin, but can be set to a shared native passkey host such "
            "as https://pr.planini.malaber.de."
        ),
    }
)
def run_ios_e2e(
    c,
    base_url=DEFAULT_IOS_E2E_BASE_URL,
    e2e_seed_path=DEFAULT_BROWSER_SEED_PATH,
    webauthn_rp_id="localhost",
    user_email=DEFAULT_IOS_E2E_USER_EMAIL,
    origin="",
) -> None:
    env = _ios_e2e_env(
        base_url=base_url,
        e2e_seed_path=e2e_seed_path,
        webauthn_rp_id=webauthn_rp_id,
        user_email=user_email,
        origin=origin,
    )
    c.run(
        "xcrun swift test --package-path ios/PlaniniIOS --filter LiveBackendE2ETests",
        env=env,
        pty=False,
        shell="/bin/bash",
    )


@task(
    help={
        "base_url": "Base URL used by the native iOS UI e2e flow.",
        "bootstrap_base_url": "Host-side base URL used by XCTest to bootstrap a seeded session.",
        "user_email": "Seeded user email used for bootstrap login into the app.",
        "artifact_dir": "Directory used to store native iOS UI screenshots.",
        "device_name": "Simulator device name used for XCUITest.",
        "initial_list_name": "Seeded list name that should open first inside the app.",
        "language": "Language used by the app during XCUITest.",
        "only_testing": "Xcode test target, class, or method passed to -only-testing.",
        "expected_width": "Optional expected screenshot width in pixels.",
        "expected_height": "Optional expected screenshot height in pixels.",
    }
)
def run_ios_ui_e2e(
    c,
    base_url=DEFAULT_IOS_UI_E2E_BASE_URL,
    bootstrap_base_url=DEFAULT_IOS_UI_E2E_BASE_URL,
    user_email=DEFAULT_IOS_E2E_USER_EMAIL,
    artifact_dir=DEFAULT_IOS_UI_E2E_ARTIFACT_DIR,
    device_name=DEFAULT_IOS_UI_E2E_DEVICE,
    initial_list_name=DEFAULT_IOS_UI_E2E_INITIAL_LIST,
    language="en",
    access_token="",
    display_name="",
    attempts=1,
    only_testing="PlaniniUITests",
    expected_width=0,
    expected_height=0,
) -> None:
    artifact_path = ROOT / artifact_dir
    artifact_path.mkdir(parents=True, exist_ok=True)
    for existing_png in artifact_path.glob("*.png"):
        existing_png.unlink()
    result_bundle_path = artifact_path / DEFAULT_IOS_UI_E2E_RESULT_BUNDLE
    shutil.rmtree(result_bundle_path, ignore_errors=True)

    env = _ios_ui_test_env(
        base_url=base_url,
        bootstrap_base_url=bootstrap_base_url,
        user_email=user_email,
        artifact_dir=artifact_dir,
        initial_list_name=initial_list_name,
        language=language,
        access_token=access_token or None,
        display_name=display_name or None,
    )
    _ensure_ios_simulator_device(device_name)
    command = " ".join(
        [
            "cd ios/PlaniniIOS &&",
            "xcodebuild",
            "-project PlaniniApp.xcodeproj",
            "-scheme Planini",
            f"-destination {shlex.quote(_ios_simulator_destination(device_name))}",
            "-destination-timeout 120",
            f"-resultBundlePath {shlex.quote(str(result_bundle_path.resolve()))}",
            "-quiet",
            "-parallel-testing-enabled NO",
            "-maximum-parallel-testing-workers 1",
            f"-only-testing:{shlex.quote(only_testing)}",
            "test",
        ]
    )
    result = None
    max_attempts = max(1, int(attempts))
    for attempt in range(max_attempts):
        shutil.rmtree(result_bundle_path, ignore_errors=True)
        result = c.run(
            command,
            env=env,
            pty=False,
            shell="/bin/bash",
            warn=True,
        )
        if result.exited == 0:
            break
        if attempt < max_attempts - 1:
            print(
                "Retrying iOS UI e2e after xcodebuild failure "
                f"(attempt {attempt + 1}/{max_attempts})..."
            )

    _write_ios_ui_e2e_summary(artifact_dir)
    assert result is not None
    if result.exited == 0 and int(expected_width) > 0 and int(expected_height) > 0:
        _validate_ios_screenshot_sizes(
            artifact_dir,
            (int(expected_width), int(expected_height)),
        )
    if result.exited != 0:
        failure_summaries = _ios_ui_e2e_failure_summaries(result_bundle_path)
        if failure_summaries:
            print("iOS UI e2e failure summary:")
            for summary in failure_summaries:
                print(f"- {summary}")
        raise Exit(f"Command failed with exit code {result.exited}: xcodebuild iOS UI e2e")


@task(
    help={
        "seed_path": "Fixture used to seed the local app database.",
        "e2e_seed_path": "Fixture that contains passkey data for the browser flow.",
        "database_url": "Database URL for the temporary local app.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the browser.",
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
    }
)
def check_browser_e2e(
    c,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    e2e_seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_BROWSER_DATABASE_URL,
    webauthn_rp_id="localhost",
    host=DEFAULT_HOST,
    port=DEFAULT_PORT,
    log_path=DEFAULT_APP_LOG_PATH,
    pid_path=DEFAULT_APP_PID_PATH,
) -> None:
    _reset_sqlite_database_file(database_url)
    start_app(
        c,
        seed_path=seed_path,
        database_url=database_url,
        webauthn_rp_id=webauthn_rp_id,
        host=host,
        port=port,
        log_path=log_path,
        pid_path=pid_path,
    )
    try:
        wait_for_app(c, url=f"http://{host}:{port}/health")
        run_browser_e2e(
            c,
            preview_base_url=f"http://localhost:{port}",
            e2e_seed_path=e2e_seed_path,
            webauthn_rp_id=webauthn_rp_id,
        )
    finally:
        stop_app(c, pid_path=pid_path)


@task(
    help={
        "backend_url": (
            "Backend URL whose hostname should be used as the WebAuthn RP ID; "
            "the deployed backend must also serve an AASA file for the signed "
            "appID on that host."
        ),
        "seed_path": "Fixture used to seed the local app database.",
        "database_url": "Database URL for the temporary local app.",
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
    }
)
def start_ios_backend(
    c,
    backend_url=DEFAULT_IOS_APP_BACKEND_URL,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_IOS_E2E_DATABASE_URL,
    host=DEFAULT_HOST,
    port=DEFAULT_IOS_E2E_PORT,
    log_path=DEFAULT_IOS_E2E_LOG_PATH,
    pid_path=DEFAULT_IOS_E2E_PID_PATH,
) -> None:
    start_app(
        c,
        seed_path=seed_path,
        database_url=database_url,
        webauthn_rp_id=_validated_ios_backend_host(backend_url),
        host=host,
        port=port,
        log_path=log_path,
        pid_path=pid_path,
    )


@task(
    help={
        "seed_path": "Fixture used to seed the local app database.",
        "e2e_seed_path": "Fixture that contains passkey data for the native iOS flow.",
        "database_url": "Database URL for the temporary local app.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the native iOS flow.",
        "user_email": "Seeded user email used for the native iOS passkey login.",
        "origin": (
            "Optional origin embedded into the seeded passkey assertion. Defaults to "
            "http://localhost:<port>, but can be overridden to model shared native "
            "passkey hosts."
        ),
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
    }
)
def check_ios_e2e(
    c,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    e2e_seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_IOS_E2E_DATABASE_URL,
    webauthn_rp_id="localhost",
    user_email=DEFAULT_IOS_E2E_USER_EMAIL,
    origin="",
    host=DEFAULT_HOST,
    port=DEFAULT_IOS_E2E_PORT,
    log_path=DEFAULT_IOS_E2E_LOG_PATH,
    pid_path=DEFAULT_IOS_E2E_PID_PATH,
) -> None:
    _reset_sqlite_database_file(database_url)
    start_app(
        c,
        seed_path=seed_path,
        database_url=database_url,
        webauthn_rp_id=webauthn_rp_id,
        host=host,
        port=port,
        log_path=log_path,
        pid_path=pid_path,
    )
    try:
        wait_for_app(c, url=f"http://{host}:{port}/health")
        run_ios_e2e(
            c,
            base_url=f"http://127.0.0.1:{port}",
            e2e_seed_path=e2e_seed_path,
            webauthn_rp_id=webauthn_rp_id,
            user_email=user_email,
            origin=origin,
        )
    finally:
        stop_app(c, pid_path=pid_path)


@task(
    help={
        "seed_path": "Fixture used to seed the local app database.",
        "database_url": "Database URL for the temporary local app.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the native app.",
        "user_email": "Seeded user email used for UI bootstrap login.",
        "artifact_dir": "Directory used to store native iOS UI screenshots.",
        "device_name": "Simulator device name used for XCUITest.",
        "initial_list_name": "Seeded list name that should open first inside the app.",
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
        "attempts": "Maximum xcodebuild attempts for transient simulator startup failures.",
        "only_testing": "Xcode test target, class, or method passed to -only-testing.",
    }
)
def check_ios_ui_e2e(
    c,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_IOS_UI_E2E_DATABASE_URL,
    webauthn_rp_id="localhost",
    user_email=DEFAULT_IOS_E2E_USER_EMAIL,
    artifact_dir=DEFAULT_IOS_UI_E2E_ARTIFACT_DIR,
    device_name=DEFAULT_IOS_UI_E2E_DEVICE,
    initial_list_name=DEFAULT_IOS_UI_E2E_INITIAL_LIST,
    host=DEFAULT_HOST,
    port=DEFAULT_IOS_UI_E2E_PORT,
    log_path=DEFAULT_IOS_UI_E2E_LOG_PATH,
    pid_path=DEFAULT_IOS_UI_E2E_PID_PATH,
    attempts=2,
    only_testing="PlaniniUITests",
) -> None:
    max_attempts = max(1, int(attempts))
    for attempt in range(max_attempts):
        _reset_sqlite_database_file(database_url)
        start_app(
            c,
            seed_path=seed_path,
            database_url=database_url,
            webauthn_rp_id=webauthn_rp_id,
            host=host,
            port=port,
            log_path=log_path,
            pid_path=pid_path,
            ui_test_bootstrap_enabled=True,
        )
        try:
            wait_for_app(c, url=f"http://{host}:{port}/health")
            session = _bootstrap_ios_ui_test_session(
                base_url=f"http://localhost:{port}",
                user_email=user_email,
            )
            if attempt == 0:
                generate_ios_app_icons.body(c)
                generate_ios_project.body(c)
            run_ios_ui_e2e(
                c,
                base_url=f"http://localhost:{port}",
                bootstrap_base_url=f"http://localhost:{port}",
                user_email=user_email,
                artifact_dir=artifact_dir,
                device_name=device_name,
                initial_list_name=initial_list_name,
                access_token=session["access_token"],
                display_name=session["display_name"],
                attempts=1,
                only_testing=only_testing,
            )
            return
        except Exit:
            if attempt >= max_attempts - 1:
                raise
            print(
                "Retrying iOS UI e2e with a fresh seeded database "
                f"(attempt {attempt + 1}/{max_attempts})..."
            )
        finally:
            stop_app(c, pid_path=pid_path)


@task
def check_ios_marketing_screenshots(
    c,
    seed_path=DEFAULT_IOS_MARKETING_SCREENSHOT_SEED_PATH,
    database_url=DEFAULT_IOS_MARKETING_SCREENSHOT_DATABASE_URL,
    webauthn_rp_id="localhost",
    user_email=DEFAULT_IOS_E2E_USER_EMAIL,
    german_user_email=DEFAULT_IOS_MARKETING_SCREENSHOT_GERMAN_USER_EMAIL,
    artifact_dir=DEFAULT_IOS_MARKETING_SCREENSHOT_ARTIFACT_DIR,
    device_name=DEFAULT_IOS_MARKETING_SCREENSHOT_DEVICE,
    ipad_device_name=DEFAULT_IOS_MARKETING_SCREENSHOT_IPAD_DEVICE,
    watch_phone_device_name=DEFAULT_IOS_MARKETING_SCREENSHOT_WATCH_PHONE_DEVICE,
    watch_device_name=DEFAULT_IOS_MARKETING_SCREENSHOT_WATCH_DEVICE,
    initial_list_name=DEFAULT_IOS_MARKETING_SCREENSHOT_INITIAL_LIST,
    german_initial_list_name=DEFAULT_IOS_MARKETING_SCREENSHOT_GERMAN_INITIAL_LIST,
    host=DEFAULT_HOST,
    port=DEFAULT_IOS_MARKETING_SCREENSHOT_PORT,
    log_path=DEFAULT_IOS_MARKETING_SCREENSHOT_LOG_PATH,
    pid_path=DEFAULT_IOS_MARKETING_SCREENSHOT_PID_PATH,
) -> None:
    """Capture App Store-sized iPhone, iPad, and watchOS screenshots."""
    shutil.rmtree(ROOT / artifact_dir, ignore_errors=True)
    _reset_sqlite_database_file(database_url)
    start_app(
        c,
        seed_path=seed_path,
        database_url=database_url,
        webauthn_rp_id=webauthn_rp_id,
        host=host,
        port=port,
        log_path=log_path,
        pid_path=pid_path,
        ui_test_bootstrap_enabled=True,
    )
    try:
        wait_for_app(c, url=f"http://{host}:{port}/health")
        generate_ios_app_icons.body(c)
        generate_ios_project.body(c)
        for locale_dir, language, locale_user_email, locale_initial_list_name in [
            ("en-US", "en", user_email, initial_list_name),
            ("de-DE", "de", german_user_email, german_initial_list_name),
        ]:
            session = _bootstrap_ios_ui_test_session(
                base_url=f"http://localhost:{port}",
                user_email=locale_user_email,
            )
            for platform_dir, platform_device_name, expected_size in [
                ("iphone", device_name, DEFAULT_IOS_MARKETING_SCREENSHOT_SIZE),
                ("ipad", ipad_device_name, DEFAULT_IOS_MARKETING_SCREENSHOT_IPAD_SIZE),
            ]:
                try:
                    run_ios_ui_e2e(
                        c,
                        base_url=f"http://localhost:{port}",
                        bootstrap_base_url=f"http://localhost:{port}",
                        user_email=locale_user_email,
                        artifact_dir=f"{artifact_dir}/{platform_dir}/{locale_dir}",
                        device_name=platform_device_name,
                        initial_list_name=locale_initial_list_name,
                        language=language,
                        access_token=session["access_token"],
                        display_name=session["display_name"],
                        only_testing=DEFAULT_IOS_MARKETING_SCREENSHOT_TEST,
                        expected_width=expected_size[0],
                        expected_height=expected_size[1],
                    )
                finally:
                    _shutdown_ios_simulators()
            try:
                _capture_watch_marketing_screenshot(
                    c,
                    base_url=f"http://localhost:{port}",
                    bootstrap_email=locale_user_email,
                    initial_list_name=locale_initial_list_name,
                    language=language,
                    locale=locale_dir,
                    artifact_dir=f"{artifact_dir}/watchos/{locale_dir}",
                    phone_device=watch_phone_device_name,
                    watch_device=watch_device_name,
                )
            finally:
                _shutdown_ios_simulators()
    finally:
        stop_app(c, pid_path=pid_path)


@task(
    pre=[
        install_xcodegen,
        check_ios_e2e,
        check_ios_ui_e2e,
        check_ios_marketing_screenshots,
    ]
)
def check_ios_ci(c) -> None:
    """Run the native iOS e2e CI flow.

    Swift package coverage runs in the separate Linux Swift CI job. The UI e2e
    task generates the Xcode project and xcodebuild test builds the simulator app.
    """


@task(
    help={
        "base_url": "Browser-facing base URL used by the Playwright flow.",
        "seed_path": "Fixture used to seed the local app database and browser flow.",
        "database_url": "Base database URL used to derive per-device SQLite files.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the browser.",
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "artifact_root": "Directory used to store per-device browser artifacts.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
    }
)
def browser_e2e(
    c,
    base_url=DEFAULT_PREVIEW_BASE_URL,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_BROWSER_DATABASE_URL,
    webauthn_rp_id="localhost",
    host=DEFAULT_HOST,
    port=DEFAULT_PORT,
    artifact_root="e2e-artifacts",
    log_path=DEFAULT_APP_LOG_PATH,
    pid_path=DEFAULT_APP_PID_PATH,
) -> None:
    """Run seeded browser e2e for desktop and iPhone and store artifacts per device."""
    for device in ("desktop", "iphone"):
        _run_browser_e2e_for_device(
            c,
            device=device,
            base_url=base_url,
            seed_path=seed_path,
            database_url=database_url,
            webauthn_rp_id=webauthn_rp_id,
            host=host,
            port=port,
            artifact_root=artifact_root,
            log_path=log_path,
            pid_path=pid_path,
        )


@task(
    help={
        "base_url": "Browser-facing base URL used by the Playwright flow.",
        "seed_path": "Fixture used to seed the local app database and browser flow.",
        "database_url": "Base database URL used to derive the desktop SQLite file.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the browser.",
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "artifact_root": "Directory used to store browser artifacts.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
    }
)
def browser_e2e_desktop(
    c,
    base_url=DEFAULT_PREVIEW_BASE_URL,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_BROWSER_DATABASE_URL,
    webauthn_rp_id="localhost",
    host=DEFAULT_HOST,
    port=DEFAULT_PORT,
    artifact_root="e2e-artifacts",
    log_path=DEFAULT_APP_LOG_PATH,
    pid_path=DEFAULT_APP_PID_PATH,
) -> None:
    """Run seeded browser e2e for desktop only."""
    _run_browser_e2e_for_device(
        c,
        device="desktop",
        base_url=base_url,
        seed_path=seed_path,
        database_url=database_url,
        webauthn_rp_id=webauthn_rp_id,
        host=host,
        port=port,
        artifact_root=artifact_root,
        log_path=log_path,
        pid_path=pid_path,
    )


@task(
    help={
        "base_url": "Browser-facing base URL used by the Playwright flow.",
        "seed_path": "Fixture used to seed the local app database and browser flow.",
        "database_url": "Base database URL used to derive the iPhone SQLite file.",
        "webauthn_rp_id": "WebAuthn relying party ID exposed to the browser.",
        "host": "Host to bind the local app server to.",
        "port": "Port to bind the local app server to.",
        "artifact_root": "Directory used to store browser artifacts.",
        "log_path": "File used for uvicorn logs.",
        "pid_path": "File used to store the started server PID.",
    }
)
def browser_e2e_mobile(
    c,
    base_url=DEFAULT_PREVIEW_BASE_URL,
    seed_path=DEFAULT_BROWSER_SEED_PATH,
    database_url=DEFAULT_BROWSER_DATABASE_URL,
    webauthn_rp_id="localhost",
    host=DEFAULT_HOST,
    port=DEFAULT_PORT,
    artifact_root="e2e-artifacts",
    log_path=DEFAULT_APP_LOG_PATH,
    pid_path=DEFAULT_APP_PID_PATH,
) -> None:
    """Run seeded browser e2e for iPhone only."""
    _run_browser_e2e_for_device(
        c,
        device="iphone",
        base_url=base_url,
        seed_path=seed_path,
        database_url=database_url,
        webauthn_rp_id=webauthn_rp_id,
        host=host,
        port=port,
        artifact_root=artifact_root,
        log_path=log_path,
        pid_path=pid_path,
    )


@task(pre=[check_python, install_js, check_js, install_browser, check_browser_e2e])
def verify(c) -> None:
    """Run the full local verification flow used before pushing."""
