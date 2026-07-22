import importlib.util
import shlex
import sqlite3
import sys
import types
from contextlib import closing
from pathlib import Path

TASKS_PATH = Path(__file__).resolve().parents[1] / "tasks.py"
TASKS_SPEC = importlib.util.spec_from_file_location("tasks", TASKS_PATH)
assert TASKS_SPEC is not None
assert TASKS_SPEC.loader is not None
tasks = importlib.util.module_from_spec(TASKS_SPEC)
TASKS_SPEC.loader.exec_module(tasks)


class RunResult:
    def __init__(self, exited: int, stdout: str = "", stderr: str = "") -> None:
        self.exited = exited
        self.stdout = stdout
        self.stderr = stderr


def test_database_url_for_device_uses_distinct_sqlite_file() -> None:
    database_url = "sqlite+aiosqlite:///./tmp-ci-ui-e2e.db"

    assert tasks._database_url_for_device(database_url, "iphone") == (
        "sqlite+aiosqlite:///./tmp-ci-ui-e2e-iphone.db"
    )


def test_database_url_for_device_leaves_non_sqlite_urls_unchanged() -> None:
    database_url = "postgresql+asyncpg://user:password@example.com/planini"

    assert tasks._database_url_for_device(database_url, "iphone") == database_url


def test_reset_sqlite_database_file_removes_database_and_sidecars(tmp_path: Path) -> None:
    database_path = tmp_path / "browser-e2e.db"
    for suffix in ("", "-shm", "-wal"):
        database_path.with_name(f"{database_path.name}{suffix}").write_text(
            "data", encoding="utf-8"
        )

    tasks._reset_sqlite_database_file(f"sqlite+aiosqlite:///{database_path}")

    for suffix in ("", "-shm", "-wal"):
        assert not database_path.with_name(f"{database_path.name}{suffix}").exists()


def test_clean_browser_e2e_removes_database_and_sidecars(tmp_path: Path) -> None:
    database_path = tmp_path / "browser-e2e.db"
    for suffix in ("", "-shm", "-wal"):
        database_path.with_name(f"{database_path.name}{suffix}").write_text(
            "data", encoding="utf-8"
        )

    tasks.clean_browser_e2e.body(None, database_url=f"sqlite+aiosqlite:///{database_path}")

    for suffix in ("", "-shm", "-wal"):
        assert not database_path.with_name(f"{database_path.name}{suffix}").exists()


def test_wait_for_pid_exit_returns_once_process_is_gone(monkeypatch) -> None:
    states = iter([True, True, False])
    monkeypatch.setattr(tasks.os, "waitpid", lambda pid, flags: (0, 0))
    monkeypatch.setattr(tasks, "_pid_is_running", lambda pid: next(states))
    monkeypatch.setattr(tasks.time, "sleep", lambda _: None)

    tasks._wait_for_pid_exit(123)


def test_wait_for_pid_exit_reaps_child_process(monkeypatch) -> None:
    monkeypatch.setattr(tasks.os, "waitpid", lambda pid, flags: (pid, 0))

    tasks._wait_for_pid_exit(123)


def test_ios_ui_e2e_failure_summaries_returns_empty_without_database(tmp_path: Path) -> None:
    assert tasks._ios_ui_e2e_failure_summaries(tmp_path / "missing.xcresult") == []


def test_ios_ui_e2e_failure_summaries_reads_failed_test_messages(tmp_path: Path) -> None:
    bundle_path = tmp_path / "PlaniniUITests.xcresult"
    bundle_path.mkdir()
    database_path = bundle_path / "database.sqlite3"

    with closing(sqlite3.connect(database_path)) as connection:
        connection.executescript(
            """
            CREATE TABLE TestCases (name TEXT);
            CREATE TABLE TestCaseRuns (testCase_fk INTEGER, result TEXT);
            CREATE TABLE TestIssues (
                testCaseRun_fk INTEGER,
                compactDescription TEXT,
                detailedDescription TEXT,
                orderInOwner INTEGER
            );
            INSERT INTO TestCases(rowid, name) VALUES (1, 'testListViewFlow()');
            INSERT INTO TestCaseRuns(rowid, testCase_fk, result) VALUES (1, 1, 'Failure');
            INSERT INTO TestIssues(
                testCaseRun_fk,
                compactDescription,
                detailedDescription,
                orderInOwner
            ) VALUES (1, 'Compact failure', 'Detailed failure', 0);
            """
        )

    assert tasks._ios_ui_e2e_failure_summaries(bundle_path) == [
        "testListViewFlow() [Failure]: Detailed failure"
    ]


def test_ios_ui_e2e_failure_summaries_reads_xcresulttool_json(tmp_path: Path, monkeypatch) -> None:
    bundle_path = tmp_path / "PlaniniUITests.xcresult"
    bundle_path.mkdir()

    class Result:
        returncode = 0
        stdout = """
        {
          "tests": [
            {
              "name": "PlaniniUITests.testListReceivesLiveUpdates()",
              "testStatus": "Failure",
              "failureSummaries": [
                {"message": "XCTAssertTrue failed while waiting for UI Live item"}
              ]
            }
          ]
        }
    """

    def fake_run(command, **kwargs):
        assert command == [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "summary",
            "--path",
            str(bundle_path),
            "--compact",
        ]
        assert kwargs == {"capture_output": True, "text": True, "check": False}
        return Result()

    monkeypatch.setattr(tasks.subprocess, "run", fake_run)

    assert tasks._ios_ui_e2e_failure_summaries(bundle_path) == [
        "PlaniniUITests.testListReceivesLiveUpdates(): "
        "XCTAssertTrue failed while waiting for UI Live item"
    ]


def test_ios_ui_e2e_failure_summaries_include_xcresult_details_and_activity(
    tmp_path: Path, monkeypatch
) -> None:
    bundle_path = tmp_path / "PlaniniUITests.xcresult"
    bundle_path.mkdir()
    commands: list[list[str]] = []

    class Result:
        returncode = 0

        def __init__(self, stdout: str) -> None:
            self.stdout = stdout

    def fake_run(command, **kwargs):
        commands.append(command)
        assert kwargs == {"capture_output": True, "text": True, "check": False}
        if command[4] == "summary":
            return Result(
                """
                {
                  "testFailures": [
                    {
                      "testName": "PlaniniUITests.testListViewFlow()",
                      "failureText": "XCTAssertTrue failed",
                      "testIdentifierString": "PlaniniUITests/testListViewFlow()"
                    }
                  ]
                }
                """
            )
        if command[4] == "test-details":
            return Result(
                """
                {
                  "testName": "PlaniniUITests.testListViewFlow()",
                  "testRuns": [
                    {
                      "nodeType": "Test Case Run",
                      "result": "Failed",
                      "children": [
                        {
                          "nodeType": "Source Code Reference",
                          "name": "PlaniniUITests.swift:95"
                        },
                        {
                          "nodeType": "Expression",
                          "name": "openAddItemSheet(using: quickAddUncategorized, in: app)"
                        }
                      ]
                    }
                  ]
                }
                """
            )
        assert command[4] == "activities"
        return Result(
            """
            {
              "testName": "PlaniniUITests.testListViewFlow()",
              "testRuns": {
                "activities": [
                  {
                    "title": "Quick add uncategorized item",
                    "childActivities": [
                      {
                        "title": "Wait for add item sheet",
                        "isAssociatedWithFailure": true
                      }
                    ]
                  }
                ]
              }
            }
            """
        )

    monkeypatch.setattr(tasks.subprocess, "run", fake_run)

    assert tasks._ios_ui_e2e_failure_summaries(bundle_path) == [
        "PlaniniUITests.testListViewFlow(): XCTAssertTrue failed",
        "PlaniniUITests.testListViewFlow(): Source: PlaniniUITests.swift:95",
        "PlaniniUITests.testListViewFlow(): "
        "Expression: openAddItemSheet(using: quickAddUncategorized, in: app)",
        "PlaniniUITests.testListViewFlow(): "
        "Failure activity: Quick add uncategorized item > Wait for add item sheet",
    ]
    assert commands == [
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "summary",
            "--path",
            str(bundle_path),
            "--compact",
        ],
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "test-details",
            "--path",
            str(bundle_path),
            "--compact",
            "--test-id",
            "PlaniniUITests/testListViewFlow()",
        ],
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "activities",
            "--path",
            str(bundle_path),
            "--compact",
            "--test-id",
            "PlaniniUITests/testListViewFlow()",
        ],
    ]


def test_ios_ui_e2e_failure_summaries_includes_xcresult_location(
    tmp_path: Path, monkeypatch
) -> None:
    bundle_path = tmp_path / "PlaniniUITests.xcresult"
    bundle_path.mkdir()

    class Result:
        returncode = 0
        stdout = """
        {
          "tests": [
            {
              "identifier": "PlaniniUITests.testListViewFlow()",
              "testStatus": "Failure",
              "failureSummaries": [
                {
                  "message": {"_value": "XCTAssertTrue failed"},
                  "sourceCodeContext": {
                    "location": {
                      "fileURL": {
                        "_value": "ios/PlaniniIOS/UITests/PlaniniUITests.swift"
                      },
                      "lineNumber": {"_value": 44}
                    }
                  }
                }
              ]
            }
          ]
        }
        """

    monkeypatch.setattr(tasks.subprocess, "run", lambda *args, **kwargs: Result())

    assert tasks._ios_ui_e2e_failure_summaries(bundle_path) == [
        "PlaniniUITests.testListViewFlow() "
        "(ios/PlaniniIOS/UITests/PlaniniUITests.swift:44): XCTAssertTrue failed"
    ]


def test_write_ios_ui_e2e_summary_includes_failure_summaries(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    artifact_path = tmp_path / "e2e-artifacts" / "ios-ui-e2e"
    artifact_path.mkdir(parents=True)
    (artifact_path / "ios-ui-list-detail.png").write_text("fake png", encoding="utf-8")
    result_bundle_path = artifact_path / tasks.DEFAULT_IOS_UI_E2E_RESULT_BUNDLE
    result_bundle_path.mkdir()
    monkeypatch.setattr(
        tasks,
        "_ios_ui_e2e_failure_summaries",
        lambda path: ["PlaniniUITests.testListViewFlow() (PlaniniUITests.swift:44): XCT failed"],
    )

    tasks._write_ios_ui_e2e_summary("e2e-artifacts/ios-ui-e2e")

    summary = (artifact_path / "summary.md").read_text(encoding="utf-8")
    assert "## Failures" in summary
    assert "- PlaniniUITests.testListViewFlow() (PlaniniUITests.swift:44): XCT failed" in summary
    assert "## Screenshots" in summary
    assert "- ios-ui-list-detail.png" in summary
    assert f"- {tasks.DEFAULT_IOS_UI_E2E_RESULT_BUNDLE}" in summary


def test_validate_ios_screenshot_sizes_accepts_expected_png_size(
    tmp_path: Path, monkeypatch
) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    artifact_path = tmp_path / "e2e-artifacts" / "ios-marketing-screenshots"
    artifact_path.mkdir(parents=True)
    png_header = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + tasks.struct.pack(">II", 1284, 2778)
    (artifact_path / "app-store-iphone-01-login.png").write_bytes(png_header)

    tasks._validate_ios_screenshot_sizes(
        "e2e-artifacts/ios-marketing-screenshots",
        (1284, 2778),
    )


def test_validate_ios_screenshot_sizes_rejects_wrong_png_size(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    artifact_path = tmp_path / "e2e-artifacts" / "ios-marketing-screenshots"
    artifact_path.mkdir(parents=True)
    png_header = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + tasks.struct.pack(">II", 1206, 2622)
    (artifact_path / "app-store-iphone-01-login.png").write_bytes(png_header)

    try:
        tasks._validate_ios_screenshot_sizes(
            "e2e-artifacts/ios-marketing-screenshots",
            (1284, 2778),
        )
    except tasks.Exit as exc:
        assert "Expected iOS screenshots sized 1284x2778" in str(exc)
        assert "app-store-iphone-01-login.png: 1206x2622" in str(exc)
    else:
        raise AssertionError("expected wrong screenshot dimensions to fail")


def test_validate_ios_screenshot_sizes_rejects_missing_and_invalid_pngs(
    tmp_path: Path, monkeypatch
) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    artifact_path = tmp_path / "e2e-artifacts" / "ios-marketing-screenshots"
    artifact_path.mkdir(parents=True)

    try:
        tasks._validate_ios_screenshot_sizes(
            "e2e-artifacts/ios-marketing-screenshots",
            (1284, 2778),
        )
    except tasks.Exit as exc:
        assert "No iOS screenshots found" in str(exc)
    else:
        raise AssertionError("expected missing screenshots to fail")

    invalid_path = artifact_path / "invalid.png"
    invalid_path.write_bytes(b"not a png")
    try:
        tasks._validate_ios_screenshot_sizes(
            "e2e-artifacts/ios-marketing-screenshots",
            (1284, 2778),
        )
    except tasks.Exit as exc:
        assert f"Invalid PNG screenshot: {invalid_path}" == str(exc)
    else:
        raise AssertionError("expected invalid PNG to fail")


def test_capture_watch_marketing_screenshot_launches_localized_watch_and_validates(
    tmp_path: Path,
    monkeypatch,
) -> None:
    calls: list[tuple[str, object]] = []
    env = {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}

    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(
        tasks,
        "_ensure_ios_simulator_device",
        lambda name: calls.append(("ensure", name)),
    )
    monkeypatch.setattr(
        tasks.run_ios_simulators_fresh,
        "body",
        lambda c, **kwargs: calls.append(("fresh", kwargs)),
    )
    monkeypatch.setattr(tasks, "_ios_toolchain_env", lambda: env)
    monkeypatch.setattr(
        tasks,
        "_find_simulator_udid",
        lambda received_env, name: calls.append(("find", (received_env, name))) or "watch-123",
    )
    monkeypatch.setattr(
        tasks,
        "_terminate_if_running",
        lambda received_env, udid, bundle_id: calls.append(
            ("terminate", (received_env, udid, bundle_id))
        ),
    )
    monkeypatch.setattr(
        tasks,
        "_run_command",
        lambda command, **kwargs: calls.append(("command", (command, kwargs))),
    )
    monkeypatch.setattr(tasks.time, "sleep", lambda seconds: calls.append(("sleep", seconds)))
    monkeypatch.setattr(
        tasks,
        "_validate_ios_screenshot_sizes",
        lambda artifact_dir, expected_size: calls.append(
            ("validate", (artifact_dir, expected_size))
        ),
    )

    tasks._capture_watch_marketing_screenshot(
        None,
        base_url="http://localhost:8019",
        bootstrap_email="planini-de@schaedler.rocks",
        initial_list_name="Wocheneinkauf",
        language="de",
        locale="de-DE",
        artifact_dir="e2e-artifacts/ios-marketing-screenshots/watchos/de-DE",
        phone_device="iPhone 17 Pro",
        watch_device="Apple Watch Ultra 3 (49mm)",
    )

    screenshot_path = (
        tmp_path
        / "e2e-artifacts"
        / "ios-marketing-screenshots"
        / "watchos"
        / "de-DE"
        / "app-store-watch-01-lists.png"
    )
    assert calls == [
        ("ensure", "Apple Watch Ultra 3 (49mm)"),
        (
            "fresh",
            {
                "phone_device": "iPhone 17 Pro",
                "watch_device": "Apple Watch Ultra 3 (49mm)",
                "derived_data_path": "ios/PlaniniIOS/.derived-marketing-watch-de",
                "backend_url_override": "http://localhost:8019",
                "bootstrap_email": "planini-de@schaedler.rocks",
                "initial_list_name": "Wocheneinkauf",
            },
        ),
        ("find", (env, "Apple Watch Ultra 3 (49mm)")),
        ("sleep", 4),
        ("terminate", (env, "watch-123", "de.malaber.planini.watchkitapp")),
        (
            "command",
            (
                [
                    "xcrun",
                    "simctl",
                    "launch",
                    "watch-123",
                    "de.malaber.planini.watchkitapp",
                    "-AppleLanguages",
                    "(de)",
                    "-AppleLocale",
                    "de_DE",
                ],
                {"env": env},
            ),
        ),
        ("sleep", 4),
        (
            "command",
            (
                ["xcrun", "simctl", "io", "watch-123", "screenshot", str(screenshot_path)],
                {"env": env},
            ),
        ),
        (
            "validate",
            (
                "e2e-artifacts/ios-marketing-screenshots/watchos/de-DE",
                (422, 514),
            ),
        ),
    ]
    assert screenshot_path.parent.is_dir()


def test_ios_simulator_destination_pins_latest_os_and_arm64_on_apple_silicon(
    monkeypatch,
) -> None:
    monkeypatch.setattr(tasks.platform, "machine", lambda: "arm64")

    assert tasks._ios_simulator_destination("iPhone 17 Pro") == (
        "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest,arch=arm64"
    )


def test_ensure_ios_simulator_device_reuses_existing_or_creates_missing(monkeypatch) -> None:
    env = {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
    boots: list[tuple[dict[str, str], str]] = []
    monkeypatch.setattr(tasks, "_ios_toolchain_env", lambda: env)
    monkeypatch.setattr(
        tasks,
        "_boot_simulator",
        lambda simulator_env, udid: boots.append((simulator_env, udid)),
    )
    monkeypatch.setattr(
        tasks,
        "_list_available_simulators",
        lambda simulator_env: {"existing": {"name": "iPhone 14 Plus"}},
    )
    tasks._ensure_ios_simulator_device("iPhone 14 Plus")
    assert boots == [(env, "existing")]

    monkeypatch.setattr(tasks, "_list_available_simulators", lambda simulator_env: {})
    monkeypatch.setattr(
        tasks,
        "_simctl_json",
        lambda simulator_env, *args: {
            "devicetypes": [
                {
                    "name": "iPhone 14 Plus",
                    "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus",
                }
            ]
        },
    )
    calls: list[tuple[list[str], dict[str, str]]] = []
    monkeypatch.setattr(
        tasks,
        "_run_command",
        lambda command, env: calls.append((command, env)),
    )
    monkeypatch.setattr(tasks, "_find_simulator_udid", lambda simulator_env, name: "created")

    tasks._ensure_ios_simulator_device("iPhone 14 Plus")

    assert calls == [
        (
            [
                "xcrun",
                "simctl",
                "create",
                "iPhone 14 Plus",
                "com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus",
            ],
            env,
        )
    ]
    assert boots == [(env, "existing"), (env, "created")]


def test_ensure_ios_simulator_device_reports_missing_type(monkeypatch) -> None:
    monkeypatch.setattr(tasks, "_ios_toolchain_env", lambda: {})
    monkeypatch.setattr(tasks, "_list_available_simulators", lambda env: {})
    monkeypatch.setattr(tasks, "_simctl_json", lambda env, *args: {"devicetypes": []})
    try:
        tasks._ensure_ios_simulator_device("iPhone 14 Plus")
    except tasks.Exit as exc:
        assert str(exc) == "iOS simulator device type is unavailable: iPhone 14 Plus"
    else:
        raise AssertionError("expected missing device type to fail")


def test_shutdown_ios_simulators_ignores_cleanup_failure(monkeypatch) -> None:
    env = {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
    calls: list[tuple[list[str], dict[str, object]]] = []
    monkeypatch.setattr(tasks, "_ios_toolchain_env", lambda: env)
    monkeypatch.setattr(
        tasks.subprocess,
        "run",
        lambda command, **kwargs: calls.append((command, kwargs)),
    )

    tasks._shutdown_ios_simulators()

    assert calls == [
        (
            ["xcrun", "simctl", "shutdown", "all"],
            {
                "env": env,
                "capture_output": True,
                "text": True,
                "check": False,
            },
        )
    ]


def test_stop_app_waits_for_exit_before_removing_pid_file(tmp_path: Path, monkeypatch) -> None:
    pid_path = tmp_path / "ui-e2e-server.pid"
    pid_path.write_text("4321\n", encoding="utf-8")
    waits: list[tuple[int, float]] = []
    signals: list[tuple[int, int]] = []

    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(tasks, "_read_pid", lambda path: 4321)
    monkeypatch.setattr(
        tasks,
        "_wait_for_pid_exit",
        lambda pid, timeout_seconds=10.0: waits.append((pid, timeout_seconds)),
    )
    monkeypatch.setattr(tasks.os, "kill", lambda pid, sig: signals.append((pid, sig)))

    tasks.stop_app.body(None, pid_path=pid_path.name)

    assert signals == [(4321, tasks.signal.SIGTERM)]
    assert waits == [(4321, 10.0)]
    assert not pid_path.exists()


def test_pid_is_running_reports_missing_process():
    assert tasks._pid_is_running(999999) is False


def test_latest_stable_version_from_tags_defaults_when_no_stable_tags():
    assert tasks._latest_stable_version_from_tags(["v1.2.3-rc.1", "notes"]) == "0.1.0"


def test_compute_version_values_for_main_uses_next_stable_tag():
    values = tasks._compute_version_values(
        ref_name="main",
        run_number=42,
        tags=["v1.2.3", "v1.2.4-rc.1"],
    )

    assert values == {
        "base_version": "1.2.4",
        "release_version": "1.2.4",
        "git_tag": "v1.2.4",
    }


def test_compute_version_values_for_branch_skips_existing_rc_tags():
    values = tasks._compute_version_values(
        ref_name="codex/workflows",
        run_number=7,
        tags=["v1.2.3", "v1.2.4-rc.7", "v1.2.4-rc.8"],
    )

    assert values == {
        "base_version": "1.2.4",
        "release_version": "1.2.4-rc.9",
        "git_tag": "v1.2.4-rc.9",
    }


def test_ios_app_icon_svg_with_background_color_updates_cls_1_fill(
    tmp_path: Path, monkeypatch
) -> None:
    source_path = tmp_path / "planini.svg"
    source_path.write_text(
        """
        <svg>
          <style>
            .cls-1 {
              fill: #ddddc1;
            }
          </style>
        </svg>
        """,
        encoding="utf-8",
    )
    monkeypatch.setattr(tasks, "IOS_APP_ICON_SOURCE_PATH", source_path)

    svg = tasks._ios_app_icon_svg_with_background_color("#A7E79D")

    assert "fill: #a7e79d;" in svg


def test_ios_app_icon_svg_with_background_color_rejects_invalid_color() -> None:
    try:
        tasks._normalize_ios_app_icon_background_color("green")
    except tasks.Exit as exc:
        assert "#rrggbb" in str(exc)
    else:
        raise AssertionError("expected invalid icon color to fail")


def test_generate_ios_app_icons_renders_variant_svg_color(tmp_path: Path, monkeypatch) -> None:
    source_path = tmp_path / "planini.svg"
    source_path.write_text(
        """
        <svg>
          <style>
            .cls-1 {
              fill: #ddddc1;
            }
          </style>
        </svg>
        """,
        encoding="utf-8",
    )
    app_iconset_path = tmp_path / "AppIcon.appiconset"
    watch_iconset_path = tmp_path / "WatchAppIcon.appiconset"
    rendered: list[dict] = []

    fake_cairosvg = types.SimpleNamespace(
        svg2png=lambda **kwargs: rendered.append(kwargs)
        or Path(kwargs["write_to"]).write_bytes(b"png")
    )

    monkeypatch.setattr(tasks, "IOS_APP_ICON_SOURCE_PATH", source_path)
    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(tasks, "IOS_APP_ICONSET_PATH", app_iconset_path)
    monkeypatch.setattr(tasks, "IOS_WATCH_APP_ICONSET_PATH", watch_iconset_path)
    monkeypatch.setattr(tasks, "IOS_APP_ICON_FILES", {"Icon-20@2x.png": 40})
    monkeypatch.setattr(tasks, "IOS_WATCH_APP_ICON_FILES", {"Icon-24@2x.png": 48})
    monkeypatch.setitem(sys.modules, "cairosvg", fake_cairosvg)

    tasks.generate_ios_app_icons.body(None, background_color="#e18585")

    assert len(rendered) == 2
    assert all(b"fill: #e18585;" in call["bytestring"] for call in rendered)
    assert (app_iconset_path / "Icon-20@2x.png").exists()
    assert (watch_iconset_path / "Icon-24@2x.png").exists()


def test_generate_ios_app_shortcuts_localizations_uses_all_locale_catalogs(
    tmp_path: Path, monkeypatch
) -> None:
    locales_path = tmp_path / "locales"
    output_path = tmp_path / "AppShortcutsLocalization"
    locales_path.mkdir()
    catalogs = {
        "en": {
            "ios": {
                "siri": {
                    "add_item_phrase": "Add Item in ${applicationName}",
                    "add_item_to_list_phrase": ("Add Item to ${list} in ${applicationName}"),
                }
            }
        },
        "de": {
            "ios": {
                "siri": {
                    "add_item_phrase": "Mit ${applicationName} hinzufügen",
                    "add_item_to_list_phrase": ("Mit ${applicationName} zu ${list} hinzufügen"),
                }
            }
        },
    }
    for locale, catalog in catalogs.items():
        (locales_path / f"{locale}.json").write_text(tasks.json.dumps(catalog), encoding="utf-8")

    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(tasks, "LOCALES_PATH", locales_path)
    monkeypatch.setattr(tasks, "IOS_APP_SHORTCUTS_LOCALIZATION_PATH", output_path)

    tasks.generate_ios_app_shortcuts_localizations.body(None)

    assert (output_path / "en.lproj" / "AppShortcuts.strings").read_text(encoding="utf-8") == (
        '"Add Item in ${applicationName}" = "Add Item in ${applicationName}";\n'
        '"Add Item to ${list} in ${applicationName}" = '
        '"Add Item to ${list} in ${applicationName}";\n'
    )
    assert (output_path / "de.lproj" / "AppShortcuts.strings").read_text(encoding="utf-8") == (
        '"Add Item in ${applicationName}" = "Mit ${applicationName} hinzufügen";\n'
        '"Add Item to ${list} in ${applicationName}" = '
        '"Mit ${applicationName} zu ${list} hinzufügen";\n'
    )


def test_ios_app_shortcuts_localizations_require_matching_placeholders() -> None:
    catalog = {
        "ios": {
            "siri": {
                "add_item_phrase": "Artikel hinzufügen",
                "add_item_to_list_phrase": "Artikel zu ${list} hinzufügen",
            }
        }
    }

    try:
        tasks._ios_app_shortcuts_strings_content(catalog, "de")
    except tasks.Exit as exc:
        assert "placeholders" in str(exc)
        assert "${applicationName}" in str(exc)
    else:
        raise AssertionError("expected missing App Shortcut placeholders to fail")


def test_ios_app_shortcuts_localizations_match_shared_locale_catalogs() -> None:
    for locale_path in sorted(tasks.LOCALES_PATH.glob("*.json")):
        locale = locale_path.stem
        catalog = tasks.json.loads(locale_path.read_text(encoding="utf-8"))
        generated_path = (
            tasks.IOS_APP_SHORTCUTS_LOCALIZATION_PATH / f"{locale}.lproj" / "AppShortcuts.strings"
        )

        assert generated_path.read_text(
            encoding="utf-8"
        ) == tasks._ios_app_shortcuts_strings_content(catalog, locale)


def test_ios_app_shortcut_source_phrases_match_swift_provider() -> None:
    provider = (tasks.ROOT / "ios" / "PlaniniIOS" / "App" / "PlaniniAppIntents.swift").read_text(
        encoding="utf-8"
    )

    for source_phrase, _ in tasks.IOS_APP_SHORTCUT_PHRASE_KEYS:
        swift_phrase = source_phrase.replace("${applicationName}", r"\(.applicationName)")
        swift_phrase = swift_phrase.replace("${list}", r"\(\.$list)")
        assert f'"{swift_phrase}"' in provider


def test_ios_testflight_workflow_adds_pr_build_component_and_variant_icon_colors() -> None:
    workflow = (
        Path(__file__).resolve().parents[1]
        / ".github"
        / "workflows"
        / "ios-build-and-testflight.yml"
    ).read_text(encoding="utf-8")

    assert "build_number_pr_component=.$pr_number" in workflow
    assert (
        "IOS_BUILD_NUMBER: ${{ github.run_number }}${{ "
        "needs.review_context.outputs.build_number_pr_component }}."
        "${{ matrix.build_variant_code }}.${{ github.run_attempt }}"
    ) in workflow
    assert '"icon_background_color":"#ddddc1"' in workflow
    assert '"icon_background_color":"#a7e79d"' in workflow
    assert '"icon_background_color":"#e18585"' in workflow
    assert "for attempt in 1 2 3; do" in workflow
    assert "Could not resolve the review PR after $attempt attempts." in workflow
    assert (
        'generate-ios-app-icons --background-color="${{ matrix.icon_background_color }}"'
        in workflow
    )
    assert "APP_STORE_CONNECT_APP_ID: '6762043307'" in workflow
    assert (
        'app_store_connect_app_id="${IOS_REVIEW_APP_STORE_CONNECT_APP_ID:-'
        '$APP_STORE_CONNECT_APP_ID}"'
    ) in workflow
    assert '--apple-id "${{ steps.variant.outputs.app_store_connect_app_id }}"' in workflow


def test_workflows_keep_portable_ios_e2e_on_linux_and_native_ui_in_ci() -> None:
    workflows = Path(__file__).resolve().parents[1] / ".github" / "workflows"
    ci_workflow = (workflows / "ci.yml").read_text(encoding="utf-8")
    testflight_workflow = (workflows / "ios-build-and-testflight.yml").read_text(encoding="utf-8")

    assert (
        "swift_test:\n    runs-on: ubuntu-latest\n    container:\n      image: swift:6.2"
        in ci_workflow
    )
    assert "path: ios/PlaniniIOS/.build" in ci_workflow
    assert "hashFiles('ios/PlaniniIOS/Package.resolved')" in ci_workflow
    assert (
        "ios_native_ui_e2e:\n    name: Native ${{ matrix.platform }} UI e2e\n    runs-on: macos-26"
        in ci_workflow
    )
    assert ci_workflow.count("check-ios-e2e") == 2
    assert "--skip-filter=listWebsocketEmitsItemLifecycleEvents" in ci_workflow
    assert "--test-filter=listWebsocketEmitsItemLifecycleEvents" in ci_workflow
    assert ci_workflow.count("check-ios-ui-e2e") == 1
    assert "check-ios-e2e" not in testflight_workflow
    assert "check-ios-ui-e2e" not in testflight_workflow
    assert "cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}" in testflight_workflow


def test_ci_skips_duplicate_main_docker_publish() -> None:
    workflow = (Path(__file__).resolve().parents[1] / ".github" / "workflows" / "ci.yml").read_text(
        encoding="utf-8"
    )

    main_skip = "if: github.ref != 'refs/heads/main'"
    assert workflow.count(main_skip) == 2
    assert f"version:\n    {main_skip}" in workflow
    assert f"docker_build_platform:\n    {main_skip}" in workflow


def test_run_quiet_hides_successful_output() -> None:
    calls: list[tuple[str, dict]] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return RunResult(exited=0, stdout="noise\n", stderr="more noise\n")

    result = tasks._run_quiet(Context(), "npm ci", pty=False)

    assert result.exited == 0
    assert calls == [("npm ci", {"pty": False, "hide": True, "warn": True})]


def test_run_quiet_prints_captured_output_on_failure(capsys) -> None:
    class Context:
        def run(self, command, **kwargs):
            return RunResult(exited=1, stdout="stdout noise\n", stderr="stderr noise")

    try:
        tasks._run_quiet(Context(), "npm ci")
    except tasks.Exit as exc:
        assert "Command failed with exit code 1: npm ci" in str(exc)
    else:
        raise AssertionError("expected quiet run failure")

    assert capsys.readouterr().out == "stdout noise\nstderr noise\n"


def test_generate_web_icons_invokes_python_script() -> None:
    calls: list[tuple[str, dict]] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))

    tasks.generate_web_icons.body(Context(), source="source.svg", output_dir="out")

    assert len(calls) == 1
    command, kwargs = calls[0]
    args = shlex.split(command)
    assert args[1:] == [
        str(tasks.ROOT / "scripts" / "generate_web_icons.py"),
        "--source",
        "source.svg",
        "--output-dir",
        "out",
    ]
    assert kwargs["env"]["PYTHONPATH"] == "."
    assert kwargs["pty"] is False
    assert kwargs["shell"] == "/bin/bash"


def test_run_browser_e2e_for_device_uses_derived_database_and_artifact_paths(monkeypatch) -> None:
    calls: list[tuple[str, dict]] = []

    monkeypatch.setattr(
        tasks,
        "_reset_sqlite_database_file",
        lambda database_url: calls.append(("reset", {"database_url": database_url})),
    )
    monkeypatch.setattr(tasks, "start_app", lambda c, **kwargs: calls.append(("start", kwargs)))
    monkeypatch.setattr(tasks, "wait_for_app", lambda c, **kwargs: calls.append(("wait", kwargs)))
    monkeypatch.setattr(tasks, "run_browser_e2e", lambda c, **kwargs: calls.append(("run", kwargs)))
    monkeypatch.setattr(tasks, "stop_app", lambda c, **kwargs: calls.append(("stop", kwargs)))

    tasks._run_browser_e2e_for_device(
        None,
        device="iphone",
        base_url="http://localhost:8000",
        seed_path="app/fixtures/review_seed_e2e.json",
        database_url="sqlite+aiosqlite:///./tmp-ui-e2e.db",
        webauthn_rp_id="localhost",
        host="127.0.0.1",
        port=8000,
        artifact_root="e2e-artifacts",
        log_path="ui-e2e-server.log",
        pid_path="ui-e2e-server.pid",
    )

    assert calls == [
        ("reset", {"database_url": "sqlite+aiosqlite:///./tmp-ui-e2e-iphone.db"}),
        (
            "start",
            {
                "seed_path": "app/fixtures/review_seed_e2e.json",
                "database_url": "sqlite+aiosqlite:///./tmp-ui-e2e-iphone.db",
                "webauthn_rp_id": "localhost",
                "host": "127.0.0.1",
                "port": 8000,
                "log_path": "ui-e2e-server.log",
                "pid_path": "ui-e2e-server.pid",
            },
        ),
        ("wait", {"url": "http://127.0.0.1:8000/health"}),
        (
            "run",
            {
                "preview_base_url": "http://localhost:8000",
                "e2e_seed_path": "app/fixtures/review_seed_e2e.json",
                "webauthn_rp_id": "localhost",
                "artifact_dir": "e2e-artifacts/ui-e2e-iphone",
                "device": "iphone",
            },
        ),
        ("stop", {"pid_path": "ui-e2e-server.pid"}),
    ]


def test_ios_e2e_env_uses_absolute_seed_and_workspace_cache(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)

    env = tasks._ios_e2e_env(
        base_url="http://localhost:8017",
        e2e_seed_path="app/fixtures/review_seed_e2e.json",
        webauthn_rp_id="localhost",
        user_email="ios@example.com",
        origin="https://passkeys.example.com",
    )

    assert env["PLANINI_E2E_BASE_URL"] == "http://localhost:8017"
    assert env["PLANINI_E2E_SEED_PATH"] == str(
        (tmp_path / "app" / "fixtures" / "review_seed_e2e.json").resolve()
    )
    assert env["PLANINI_E2E_USER_EMAIL"] == "ios@example.com"
    assert env["PLANINI_E2E_RP_ID"] == "localhost"
    assert env["PLANINI_E2E_ORIGIN"] == "https://passkeys.example.com"
    assert env["DEVELOPER_DIR"] == "/Applications/Xcode.app/Contents/Developer"
    assert env["CLANG_MODULE_CACHE_PATH"] == str(
        (tmp_path / "ios" / "PlaniniIOS" / ".clang-module-cache").resolve()
    )


def test_ios_toolchain_env_uses_workspace_cache(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)

    env = tasks._ios_toolchain_env()

    assert env["DEVELOPER_DIR"] == "/Applications/Xcode.app/Contents/Developer"
    assert env["CLANG_MODULE_CACHE_PATH"] == str(
        (tmp_path / "ios" / "PlaniniIOS" / ".clang-module-cache").resolve()
    )


def test_ios_ui_test_env_uses_absolute_artifact_path(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(
        tasks,
        "_ios_toolchain_env",
        lambda: {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"},
    )

    env = tasks._ios_ui_test_env(
        base_url="http://localhost:8018",
        bootstrap_base_url="http://localhost:8018",
        user_email="ios@example.com",
        artifact_dir="e2e-artifacts/ios-ui-e2e",
        initial_list_name="Browser Test Shop",
    )

    assert env["PLANINI_UI_TEST_BASE_URL"] == "http://localhost:8018"
    assert env["PLANINI_UI_TEST_BOOTSTRAP_BASE_URL"] == "http://localhost:8018"
    assert env["PLANINI_UI_TEST_USER_EMAIL"] == "ios@example.com"
    assert env["PLANINI_UI_TEST_INITIAL_LIST_NAME"] == "Browser Test Shop"
    assert env["PLANINI_UI_TEST_LANGUAGE"] == "en"
    assert env["PLANINI_UI_TEST_ARTIFACT_DIR"] == str(
        (tmp_path / "e2e-artifacts" / "ios-ui-e2e").resolve()
    )


def test_ios_ui_test_env_includes_injected_session_values(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(
        tasks,
        "_ios_toolchain_env",
        lambda: {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"},
    )

    env = tasks._ios_ui_test_env(
        base_url="http://localhost:8018",
        bootstrap_base_url="http://localhost:8018",
        user_email="ios@example.com",
        artifact_dir="e2e-artifacts/ios-ui-e2e",
        initial_list_name="Browser Test Shop",
        access_token="test-token",
        display_name="Test User",
    )

    assert env["PLANINI_UI_TEST_ACCESS_TOKEN"] == "test-token"
    assert env["PLANINI_UI_TEST_DISPLAY_NAME"] == "Test User"


def test_bootstrap_ios_ui_test_session_returns_access_token(monkeypatch) -> None:
    captured: dict[str, object] = {}

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self) -> bytes:
            return b'{"access_token":"token-123","display_name":"Test User"}'

    def fake_urlopen(request, timeout):
        captured["url"] = request.full_url
        captured["method"] = request.get_method()
        captured["body"] = request.data.decode("utf-8")
        captured["timeout"] = timeout
        return Response()

    monkeypatch.setattr(tasks, "urlopen", fake_urlopen)

    session = tasks._bootstrap_ios_ui_test_session(
        base_url="http://localhost:8018",
        user_email="ios@example.com",
    )

    assert session == {"access_token": "token-123", "display_name": "Test User"}
    assert captured == {
        "url": "http://localhost:8018/api/v1/auth/ui-test-bootstrap",
        "method": "POST",
        "body": '{"email": "ios@example.com"}',
        "timeout": 10,
    }


def test_bootstrap_ios_ui_test_session_rejects_incomplete_payload(monkeypatch) -> None:
    class Response:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self) -> bytes:
            return b'{"display_name":"Test User"}'

    monkeypatch.setattr(tasks, "urlopen", lambda request, timeout: Response())

    try:
        tasks._bootstrap_ios_ui_test_session(
            base_url="http://localhost:8018",
            user_email="ios@example.com",
        )
    except tasks.Exit as exc:
        assert "incomplete payload" in str(exc)
    else:
        raise AssertionError("expected incomplete iOS UI bootstrap payload to fail")


def test_validated_ios_backend_host_rejects_invalid_urls() -> None:
    try:
        tasks._validated_ios_backend_host("notaurl")
    except tasks.Exit as exc:
        assert "configure-ios-app requires a valid http or https backend_url." in str(exc)
    else:
        raise AssertionError("expected invalid backend URL to fail")


def test_write_ios_entitlements_uses_configured_host(tmp_path: Path, monkeypatch) -> None:
    entitlements_path = tmp_path / "Planini.entitlements"
    monkeypatch.setattr(tasks, "IOS_ENTITLEMENTS_PATH", entitlements_path)

    tasks._write_ios_entitlements("example.com")

    contents = entitlements_path.read_text(encoding="utf-8")
    assert "applinks:example.com" in contents
    assert "webcredentials:example.com" in contents


def test_configure_ios_app_updates_project_and_entitlements(monkeypatch, tmp_path: Path) -> None:
    project_path = tmp_path / "project.yml"
    project_path.write_text(
        "\n".join(
            [
                "PRODUCT_BUNDLE_IDENTIFIER: com.example.old",
                "DEVELOPMENT_TEAM: OLDTEAM123",
                "INFOPLIST_KEY_PlaniniBackendBaseURL: https://old.example.com",
                "",
            ]
        ),
        encoding="utf-8",
    )
    entitlements_path = tmp_path / "Planini.entitlements"
    generated_config_path = tmp_path / "BuildConfiguration.generated.swift"
    calls: list[str] = []

    monkeypatch.setattr(tasks, "IOS_PROJECT_YML_PATH", project_path)
    monkeypatch.setattr(tasks, "IOS_ENTITLEMENTS_PATH", entitlements_path)
    monkeypatch.setattr(tasks, "IOS_GENERATED_CONFIG_PATH", generated_config_path)
    monkeypatch.setattr(tasks.install_xcodegen, "body", lambda c: calls.append("install_xcodegen"))
    monkeypatch.setattr(
        tasks.generate_ios_project, "body", lambda c: calls.append("generate_ios_project")
    )

    tasks.configure_ios_app.body(
        None,
        backend_url="https://selfhost.example.com",
        passkey_domain="passkeys.example.com",
        bundle_id="com.example.selfhost",
        development_team="NEWTEAM456",
        regenerate_project=True,
    )

    project_contents = project_path.read_text(encoding="utf-8")
    assert "PRODUCT_BUNDLE_IDENTIFIER: com.example.selfhost" in project_contents
    assert "DEVELOPMENT_TEAM: NEWTEAM456" in project_contents
    assert "INFOPLIST_KEY_PlaniniBackendBaseURL: https://selfhost.example.com" in project_contents
    entitlements_contents = entitlements_path.read_text(encoding="utf-8")
    assert "applinks:passkeys.example.com" in entitlements_contents
    assert "webcredentials:passkeys.example.com" in entitlements_contents
    assert (
        'static let backendURL = "https://selfhost.example.com"'
        in generated_config_path.read_text(encoding="utf-8")
    )
    assert calls == ["install_xcodegen", "generate_ios_project"]


def test_start_ios_backend_derives_rp_id_from_backend_url(monkeypatch) -> None:
    calls: list[dict] = []

    monkeypatch.setattr(tasks, "start_app", lambda c, **kwargs: calls.append(kwargs))

    tasks.start_ios_backend.body(
        None,
        backend_url="https://shopping.example.com",
        seed_path="app/fixtures/review_seed_e2e.json",
        database_url="sqlite+aiosqlite:///./tmp-ios-e2e.db",
        host="127.0.0.1",
        port=8017,
        log_path="ios-e2e-server.log",
        pid_path="ios-e2e-server.pid",
    )

    assert calls == [
        {
            "seed_path": "app/fixtures/review_seed_e2e.json",
            "database_url": "sqlite+aiosqlite:///./tmp-ios-e2e.db",
            "webauthn_rp_id": "shopping.example.com",
            "host": "127.0.0.1",
            "port": 8017,
            "log_path": "ios-e2e-server.log",
            "pid_path": "ios-e2e-server.pid",
        }
    ]


def test_check_ios_package_invokes_swift_test(monkeypatch) -> None:
    calls: list[tuple[str, dict]] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return RunResult(exited=0)

    monkeypatch.setattr(
        tasks,
        "_ios_toolchain_env",
        lambda: {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"},
    )

    tasks.check_ios_package.body(Context(), package_path="ios/PlaniniIOS")

    assert calls == [
        (
            "xcrun swift test --package-path ios/PlaniniIOS --enable-code-coverage",
            {
                "env": {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"},
                "pty": False,
                "shell": "/bin/bash",
            },
        )
    ]


def test_generate_ios_project_invokes_xcodegen() -> None:
    calls: list[tuple[str, dict]] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return RunResult(exited=0)

    tasks.generate_ios_project.body(Context(), project_dir="ios/PlaniniIOS")

    assert calls == [
        (
            "cd ios/PlaniniIOS && xcodegen generate",
            {
                "pty": False,
                "shell": "/bin/bash",
            },
        )
    ]


def test_install_xcodegen_invokes_brew() -> None:
    calls: list[tuple[str, dict]] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return RunResult(exited=0)

    tasks.install_xcodegen.body(Context())

    assert calls == [
        (
            "brew list xcodegen >/dev/null 2>&1 || brew install xcodegen",
            {
                "pty": False,
                "shell": "/bin/bash",
            },
        )
    ]


def test_build_ios_simulator_invokes_xcodebuild(monkeypatch) -> None:
    calls: list[tuple[str, dict]] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return RunResult(exited=0)

    monkeypatch.setattr(
        tasks,
        "_ios_toolchain_env",
        lambda: {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"},
    )

    tasks.build_ios_simulator.body(
        Context(),
        project_dir="ios/PlaniniIOS",
        scheme="Planini",
        configuration="Debug",
        destination="generic/platform=iOS Simulator",
    )

    assert calls == [
        (
            "cd ios/PlaniniIOS && "
            "xcodebuild -project PlaniniApp.xcodeproj "
            "-scheme Planini "
            "-configuration Debug "
            "-destination 'generic/platform=iOS Simulator' "
            "-quiet "
            "CODE_SIGNING_ALLOWED=NO build",
            {
                "env": {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"},
                "pty": False,
                "shell": "/bin/bash",
            },
        )
    ]


def test_run_ios_e2e_invokes_swift_test_with_expected_env(monkeypatch) -> None:
    calls: list[tuple[str, dict]] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return RunResult(exited=0)

    monkeypatch.setattr(
        tasks,
        "_ios_e2e_env",
        lambda **kwargs: {
            "PLANINI_E2E_BASE_URL": kwargs["base_url"],
            "PLANINI_E2E_SEED_PATH": kwargs["e2e_seed_path"],
            "PLANINI_E2E_RP_ID": kwargs["webauthn_rp_id"],
            "PLANINI_E2E_USER_EMAIL": kwargs["user_email"],
            "PLANINI_E2E_ORIGIN": kwargs["origin"],
        },
    )

    tasks.run_ios_e2e.body(
        Context(),
        base_url="http://localhost:8017",
        e2e_seed_path="app/fixtures/review_seed_e2e.json",
        webauthn_rp_id="localhost",
        user_email="ios@example.com",
        origin="https://passkeys.example.com",
        test_filter="accountRegistrationCreatesUsableAccount|seededPasskeyLoginAndListCrud",
        skip_filter="listWebsocketEmitsItemLifecycleEvents",
    )

    assert calls == [
        (
            "swift test --package-path ios/PlaniniIOS "
            "--filter 'accountRegistrationCreatesUsableAccount|seededPasskeyLoginAndListCrud' "
            "--skip listWebsocketEmitsItemLifecycleEvents",
            {
                "env": {
                    "PLANINI_E2E_BASE_URL": "http://localhost:8017",
                    "PLANINI_E2E_SEED_PATH": "app/fixtures/review_seed_e2e.json",
                    "PLANINI_E2E_RP_ID": "localhost",
                    "PLANINI_E2E_USER_EMAIL": "ios@example.com",
                    "PLANINI_E2E_ORIGIN": "https://passkeys.example.com",
                },
                "pty": False,
                "shell": "/bin/bash",
            },
        )
    ]


def test_run_ios_ui_e2e_invokes_xcodebuild_with_expected_env(monkeypatch, tmp_path: Path) -> None:
    calls: list[tuple[str, dict]] = []
    resets: list[str] = []

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return RunResult(exited=0)

    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(
        tasks,
        "_ios_simulator_destination",
        lambda device_name: f"platform=iOS Simulator,name={device_name},OS=latest",
    )
    monkeypatch.setattr(tasks, "_ensure_ios_simulator_device", lambda device_name: None)
    monkeypatch.setattr(
        tasks, "_reset_ios_ui_test_app", lambda device_name: resets.append(device_name)
    )
    artifact_path = tmp_path / "e2e-artifacts" / "ios-ui-e2e"
    result_bundle_path = artifact_path / tasks.DEFAULT_IOS_UI_E2E_RESULT_BUNDLE
    result_bundle_path.mkdir(parents=True)
    monkeypatch.setattr(
        tasks,
        "_ios_ui_test_env",
        lambda **kwargs: {
            "PLANINI_UI_TEST_BASE_URL": kwargs["base_url"],
            "PLANINI_UI_TEST_BOOTSTRAP_BASE_URL": kwargs["bootstrap_base_url"],
            "PLANINI_UI_TEST_USER_EMAIL": kwargs["user_email"],
            "PLANINI_UI_TEST_ARTIFACT_DIR": kwargs["artifact_dir"],
            "PLANINI_UI_TEST_INITIAL_LIST_NAME": kwargs["initial_list_name"],
            "PLANINI_UI_TEST_LANGUAGE": kwargs["language"],
            "PLANINI_UI_TEST_ACCESS_TOKEN": kwargs["access_token"],
            "PLANINI_UI_TEST_DISPLAY_NAME": kwargs["display_name"],
        },
    )
    summaries: list[str] = []
    validations: list[tuple[str, tuple[int, int]]] = []
    monkeypatch.setattr(
        tasks, "_write_ios_ui_e2e_summary", lambda artifact_dir: summaries.append(artifact_dir)
    )
    monkeypatch.setattr(
        tasks,
        "_validate_ios_screenshot_sizes",
        lambda artifact_dir, expected_size: validations.append((artifact_dir, expected_size)),
    )

    tasks.run_ios_ui_e2e.body(
        Context(),
        base_url="http://localhost:8018",
        bootstrap_base_url="http://localhost:8018",
        user_email="ios@example.com",
        artifact_dir="e2e-artifacts/ios-ui-e2e",
        device_name="iPhone 17",
        initial_list_name="Browser Test Shop",
        access_token="token-123",
        display_name="Test User",
        expected_width=1284,
        expected_height=2778,
        only_testing="PlaniniUITests/PlaniniUITests/testUsesNativeIPadCanvasWhenRunningOnIPad",
    )

    assert calls == [
        (
            "cd ios/PlaniniIOS && xcodebuild -project PlaniniApp.xcodeproj "
            "-scheme Planini -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' "
            "-destination-timeout 120 "
            f"-resultBundlePath {str(result_bundle_path.resolve())} -quiet "
            "-parallel-testing-enabled NO -maximum-parallel-testing-workers 1 "
            "-only-testing:PlaniniUITests/PlaniniUITests/"
            "testUsesNativeIPadCanvasWhenRunningOnIPad test",
            {
                "env": {
                    "PLANINI_UI_TEST_BASE_URL": "http://localhost:8018",
                    "PLANINI_UI_TEST_BOOTSTRAP_BASE_URL": "http://localhost:8018",
                    "PLANINI_UI_TEST_USER_EMAIL": "ios@example.com",
                    "PLANINI_UI_TEST_ARTIFACT_DIR": "e2e-artifacts/ios-ui-e2e",
                    "PLANINI_UI_TEST_INITIAL_LIST_NAME": "Browser Test Shop",
                    "PLANINI_UI_TEST_LANGUAGE": "en",
                    "PLANINI_UI_TEST_ACCESS_TOKEN": "token-123",
                    "PLANINI_UI_TEST_DISPLAY_NAME": "Test User",
                },
                "pty": False,
                "shell": "/bin/bash",
                "warn": True,
            },
        )
    ]
    assert summaries == ["e2e-artifacts/ios-ui-e2e"]
    assert validations == [("e2e-artifacts/ios-ui-e2e", (1284, 2778))]
    assert resets == ["iPhone 17"]
    assert not result_bundle_path.exists()


def test_run_ios_ui_e2e_retries_once_before_succeeding(monkeypatch, tmp_path: Path, capsys) -> None:
    calls: list[tuple[str, dict]] = []
    resets: list[str] = []
    results = iter([RunResult(exited=65), RunResult(exited=0)])

    class Context:
        def run(self, command, **kwargs):
            calls.append((command, kwargs))
            return next(results)

    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(tasks, "_ensure_ios_simulator_device", lambda device_name: None)
    monkeypatch.setattr(
        tasks, "_reset_ios_ui_test_app", lambda device_name: resets.append(device_name)
    )
    monkeypatch.setattr(tasks, "_ios_ui_test_env", lambda **kwargs: {})
    monkeypatch.setattr(tasks, "_write_ios_ui_e2e_summary", lambda artifact_dir: None)

    tasks.run_ios_ui_e2e.body(
        Context(),
        artifact_dir="e2e-artifacts/ios-ui-e2e",
        attempts=2,
    )

    assert len(calls) == 2
    assert resets == [tasks.DEFAULT_IOS_UI_E2E_DEVICE, tasks.DEFAULT_IOS_UI_E2E_DEVICE]
    assert capsys.readouterr().out.count("Retrying iOS UI e2e after xcodebuild failure") == 1


def test_run_ios_ui_e2e_prints_failure_summary_before_exiting(
    monkeypatch, tmp_path: Path, capsys
) -> None:
    class Context:
        def run(self, command, **kwargs):
            return RunResult(exited=65)

    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    monkeypatch.setattr(tasks, "_ensure_ios_simulator_device", lambda device_name: None)
    monkeypatch.setattr(tasks, "_reset_ios_ui_test_app", lambda device_name: None)
    monkeypatch.setattr(tasks, "_ios_ui_test_env", lambda **kwargs: {})
    monkeypatch.setattr(tasks, "_write_ios_ui_e2e_summary", lambda artifact_dir: None)
    monkeypatch.setattr(
        tasks,
        "_ios_ui_e2e_failure_summaries",
        lambda result_bundle_path: ["testListViewFlow() [Failure]: Timed out waiting for response"],
    )

    try:
        tasks.run_ios_ui_e2e.body(Context(), artifact_dir="e2e-artifacts/ios-ui-e2e")
    except tasks.Exit as exc:
        assert "exit code 65" in str(exc)
    else:
        raise AssertionError("expected run_ios_ui_e2e to fail")

    captured = capsys.readouterr()
    assert "Retrying iOS UI e2e after xcodebuild failure" not in captured.out
    assert "iOS UI e2e failure summary:" in captured.out
    assert "testListViewFlow() [Failure]: Timed out waiting for response" in captured.out


def test_reset_ios_ui_test_app_uninstalls_target_app(monkeypatch) -> None:
    env = {"DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
    calls: list[tuple[str, str, str]] = []

    monkeypatch.setattr(tasks, "_ios_toolchain_env", lambda: env)
    monkeypatch.setattr(tasks, "_find_simulator_udid", lambda actual_env, name: "device-id")
    monkeypatch.setattr(
        tasks,
        "_terminate_if_running",
        lambda actual_env, udid, bundle_id: calls.append(("terminate", udid, bundle_id)),
    )
    monkeypatch.setattr(
        tasks,
        "_uninstall_if_present",
        lambda actual_env, udid, bundle_id: calls.append(("uninstall", udid, bundle_id)),
    )

    tasks._reset_ios_ui_test_app("iPhone 17")

    assert calls == [
        ("terminate", "device-id", tasks.DEFAULT_IOS_APP_BUNDLE_IDENTIFIER),
        ("uninstall", "device-id", tasks.DEFAULT_IOS_APP_BUNDLE_IDENTIFIER),
    ]


def test_check_ios_e2e_starts_waits_runs_and_stops(monkeypatch) -> None:
    calls: list[tuple[str, dict]] = []

    monkeypatch.setattr(
        tasks,
        "_reset_sqlite_database_file",
        lambda database_url: calls.append(("reset", {"database_url": database_url})),
    )
    monkeypatch.setattr(tasks, "start_app", lambda c, **kwargs: calls.append(("start", kwargs)))
    monkeypatch.setattr(tasks, "wait_for_app", lambda c, **kwargs: calls.append(("wait", kwargs)))
    monkeypatch.setattr(tasks, "run_ios_e2e", lambda c, **kwargs: calls.append(("run", kwargs)))
    monkeypatch.setattr(tasks, "stop_app", lambda c, **kwargs: calls.append(("stop", kwargs)))

    tasks.check_ios_e2e.body(
        None,
        seed_path="app/fixtures/review_seed_e2e.json",
        e2e_seed_path="app/fixtures/review_seed_e2e.json",
        database_url="sqlite+aiosqlite:///./tmp-ios-e2e.db",
        webauthn_rp_id="localhost",
        user_email="ios@example.com",
        origin="https://passkeys.example.com",
        test_filter="LiveBackendE2ETests",
        skip_filter="listWebsocketEmitsItemLifecycleEvents",
        host="127.0.0.1",
        port=8017,
        log_path="ios-e2e-server.log",
        pid_path="ios-e2e-server.pid",
    )

    assert calls == [
        ("reset", {"database_url": "sqlite+aiosqlite:///./tmp-ios-e2e.db"}),
        (
            "start",
            {
                "seed_path": "app/fixtures/review_seed_e2e.json",
                "database_url": "sqlite+aiosqlite:///./tmp-ios-e2e.db",
                "webauthn_rp_id": "localhost",
                "host": "127.0.0.1",
                "port": 8017,
                "log_path": "ios-e2e-server.log",
                "pid_path": "ios-e2e-server.pid",
            },
        ),
        ("wait", {"url": "http://127.0.0.1:8017/health"}),
        (
            "run",
            {
                "base_url": "http://127.0.0.1:8017",
                "e2e_seed_path": "app/fixtures/review_seed_e2e.json",
                "webauthn_rp_id": "localhost",
                "user_email": "ios@example.com",
                "origin": "https://passkeys.example.com",
                "test_filter": "LiveBackendE2ETests",
                "skip_filter": "listWebsocketEmitsItemLifecycleEvents",
            },
        ),
        ("stop", {"pid_path": "ios-e2e-server.pid"}),
    ]


def test_check_ios_ui_e2e_starts_waits_runs_and_stops(monkeypatch) -> None:
    calls: list[tuple[str, dict]] = []

    monkeypatch.setattr(
        tasks,
        "_reset_sqlite_database_file",
        lambda database_url: calls.append(("reset", {"database_url": database_url})),
    )
    monkeypatch.setattr(tasks, "start_app", lambda c, **kwargs: calls.append(("start", kwargs)))
    monkeypatch.setattr(tasks, "wait_for_app", lambda c, **kwargs: calls.append(("wait", kwargs)))
    monkeypatch.setattr(
        tasks,
        "_bootstrap_ios_ui_test_session",
        lambda **kwargs: calls.append(("bootstrap", kwargs))
        or {"access_token": "token-123", "display_name": "Test User"},
    )
    monkeypatch.setattr(
        tasks.generate_ios_project, "body", lambda c: calls.append(("generate", {}))
    )
    monkeypatch.setattr(tasks, "run_ios_ui_e2e", lambda c, **kwargs: calls.append(("run", kwargs)))
    monkeypatch.setattr(tasks, "stop_app", lambda c, **kwargs: calls.append(("stop", kwargs)))

    tasks.check_ios_ui_e2e.body(
        None,
        seed_path="app/fixtures/review_seed_e2e.json",
        database_url="sqlite+aiosqlite:///./tmp-ios-ui-e2e.db",
        webauthn_rp_id="localhost",
        user_email="ios@example.com",
        artifact_dir="e2e-artifacts/ios-ui-e2e",
        device_name="iPhone 17",
        initial_list_name="Browser Test Shop",
        attempts=3,
        host="127.0.0.1",
        port=8018,
        log_path="ios-ui-e2e-server.log",
        pid_path="ios-ui-e2e-server.pid",
        only_testing="PlaniniUITests/PlaniniUITests/testUsesNativeIPadCanvasWhenRunningOnIPad",
    )

    assert calls == [
        ("reset", {"database_url": "sqlite+aiosqlite:///./tmp-ios-ui-e2e.db"}),
        (
            "start",
            {
                "seed_path": "app/fixtures/review_seed_e2e.json",
                "database_url": "sqlite+aiosqlite:///./tmp-ios-ui-e2e.db",
                "webauthn_rp_id": "localhost",
                "host": "127.0.0.1",
                "port": 8018,
                "log_path": "ios-ui-e2e-server.log",
                "pid_path": "ios-ui-e2e-server.pid",
                "ui_test_bootstrap_enabled": True,
            },
        ),
        ("wait", {"url": "http://127.0.0.1:8018/health"}),
        (
            "bootstrap",
            {
                "base_url": "http://localhost:8018",
                "user_email": "ios@example.com",
            },
        ),
        ("generate", {}),
        (
            "run",
            {
                "base_url": "http://localhost:8018",
                "bootstrap_base_url": "http://localhost:8018",
                "user_email": "ios@example.com",
                "artifact_dir": "e2e-artifacts/ios-ui-e2e",
                "device_name": "iPhone 17",
                "initial_list_name": "Browser Test Shop",
                "access_token": "token-123",
                "display_name": "Test User",
                "attempts": 1,
                "only_testing": (
                    "PlaniniUITests/PlaniniUITests/testUsesNativeIPadCanvasWhenRunningOnIPad"
                ),
            },
        ),
        ("stop", {"pid_path": "ios-ui-e2e-server.pid"}),
    ]


def test_check_ios_ui_e2e_restarts_backend_before_retry(monkeypatch, capsys) -> None:
    calls: list[tuple[str, dict]] = []
    sessions = iter(
        [
            {"access_token": "token-first", "display_name": "First User"},
            {"access_token": "token-second", "display_name": "Second User"},
        ]
    )
    outcomes = iter([tasks.Exit("first attempt failed"), None])

    monkeypatch.setattr(
        tasks,
        "_reset_sqlite_database_file",
        lambda database_url: calls.append(("reset", {"database_url": database_url})),
    )
    monkeypatch.setattr(tasks, "start_app", lambda c, **kwargs: calls.append(("start", kwargs)))
    monkeypatch.setattr(tasks, "wait_for_app", lambda c, **kwargs: calls.append(("wait", kwargs)))
    monkeypatch.setattr(tasks, "_bootstrap_ios_ui_test_session", lambda **kwargs: next(sessions))
    monkeypatch.setattr(tasks.generate_ios_app_icons, "body", lambda c: calls.append(("icons", {})))
    monkeypatch.setattr(
        tasks.generate_ios_project, "body", lambda c: calls.append(("generate", {}))
    )

    def run_ios_ui_e2e(c, **kwargs):
        calls.append(("run", kwargs))
        outcome = next(outcomes)
        if outcome is not None:
            raise outcome

    monkeypatch.setattr(tasks, "run_ios_ui_e2e", run_ios_ui_e2e)
    monkeypatch.setattr(tasks, "stop_app", lambda c, **kwargs: calls.append(("stop", kwargs)))

    tasks.check_ios_ui_e2e.body(None, attempts=2)

    assert [name for name, _ in calls].count("reset") == 2
    assert [name for name, _ in calls].count("start") == 2
    assert [name for name, _ in calls].count("stop") == 2
    assert [name for name, _ in calls].count("icons") == 1
    assert [name for name, _ in calls].count("generate") == 1
    run_calls = [kwargs for name, kwargs in calls if name == "run"]
    assert [kwargs["access_token"] for kwargs in run_calls] == ["token-first", "token-second"]
    assert all(kwargs["attempts"] == 1 for kwargs in run_calls)
    assert "Retrying iOS UI e2e with a fresh backend (attempt 1/2)" in capsys.readouterr().out


def test_check_ios_ui_e2e_stops_backend_after_final_failure(monkeypatch) -> None:
    stops: list[dict] = []

    monkeypatch.setattr(tasks, "_reset_sqlite_database_file", lambda database_url: None)
    monkeypatch.setattr(tasks, "start_app", lambda c, **kwargs: None)
    monkeypatch.setattr(tasks, "wait_for_app", lambda c, **kwargs: None)
    monkeypatch.setattr(
        tasks,
        "_bootstrap_ios_ui_test_session",
        lambda **kwargs: {"access_token": "token", "display_name": "Test User"},
    )
    monkeypatch.setattr(tasks.generate_ios_app_icons, "body", lambda c: None)
    monkeypatch.setattr(tasks.generate_ios_project, "body", lambda c: None)
    monkeypatch.setattr(
        tasks,
        "run_ios_ui_e2e",
        lambda c, **kwargs: (_ for _ in ()).throw(tasks.Exit("xcode failed")),
    )
    monkeypatch.setattr(tasks, "stop_app", lambda c, **kwargs: stops.append(kwargs))

    try:
        tasks.check_ios_ui_e2e.body(None, attempts=1)
    except tasks.Exit as exc:
        assert "xcode failed" in str(exc)
    else:
        raise AssertionError("expected check_ios_ui_e2e to fail")

    assert stops == [{"pid_path": tasks.DEFAULT_IOS_UI_E2E_PID_PATH}]


def test_check_ios_marketing_screenshots_uses_polished_fixture_and_app_store_size(
    monkeypatch,
    tmp_path: Path,
) -> None:
    calls: list[tuple[str, dict]] = []

    monkeypatch.setattr(tasks, "ROOT", tmp_path)
    stale_artifact = tmp_path / "e2e-artifacts" / "ios-marketing-screenshots" / "old-screenshot.png"
    stale_artifact.parent.mkdir(parents=True)
    stale_artifact.write_bytes(b"old")
    monkeypatch.setattr(
        tasks,
        "_reset_sqlite_database_file",
        lambda database_url: calls.append(("reset", {"database_url": database_url})),
    )
    monkeypatch.setattr(tasks, "start_app", lambda c, **kwargs: calls.append(("start", kwargs)))
    monkeypatch.setattr(tasks, "wait_for_app", lambda c, **kwargs: calls.append(("wait", kwargs)))
    monkeypatch.setattr(
        tasks,
        "_bootstrap_ios_ui_test_session",
        lambda **kwargs: calls.append(("bootstrap", kwargs))
        or {
            "access_token": f"{kwargs['user_email']}-token",
            "display_name": "Alex",
        },
    )
    monkeypatch.setattr(
        tasks.generate_ios_app_icons, "body", lambda c: calls.append(("generate-icons", {}))
    )
    monkeypatch.setattr(
        tasks.generate_ios_project, "body", lambda c: calls.append(("generate", {}))
    )
    monkeypatch.setattr(tasks, "run_ios_ui_e2e", lambda c, **kwargs: calls.append(("run", kwargs)))
    monkeypatch.setattr(
        tasks,
        "_capture_watch_marketing_screenshot",
        lambda c, **kwargs: calls.append(("watch", kwargs)),
    )
    monkeypatch.setattr(
        tasks,
        "_shutdown_ios_simulators",
        lambda: calls.append(("shutdown", {})),
    )
    monkeypatch.setattr(tasks, "stop_app", lambda c, **kwargs: calls.append(("stop", kwargs)))

    tasks.check_ios_marketing_screenshots.body(None)

    run_calls = [call for call in calls if call[0] == "run"]
    assert calls[0] == (
        "reset",
        {"database_url": "sqlite+aiosqlite:///./tmp-ios-marketing-screenshots.db"},
    )
    assert not stale_artifact.exists()
    assert next(call for call in calls if call[0] == "start")[1]["seed_path"] == (
        "app/fixtures/ios_marketing_seed.json"
    )
    assert [
        (
            run_call[1]["user_email"],
            run_call[1]["artifact_dir"],
            run_call[1]["initial_list_name"],
            run_call[1]["language"],
        )
        for run_call in run_calls
    ] == [
        (
            "planini@schaedler.rocks",
            "e2e-artifacts/ios-marketing-screenshots/iphone/en-US",
            "Weekly groceries",
            "en",
        ),
        (
            "planini@schaedler.rocks",
            "e2e-artifacts/ios-marketing-screenshots/ipad/en-US",
            "Weekly groceries",
            "en",
        ),
        (
            "planini-de@schaedler.rocks",
            "e2e-artifacts/ios-marketing-screenshots/iphone/de-DE",
            "Wocheneinkauf",
            "de",
        ),
        (
            "planini-de@schaedler.rocks",
            "e2e-artifacts/ios-marketing-screenshots/ipad/de-DE",
            "Wocheneinkauf",
            "de",
        ),
    ]
    assert [run_call[1]["device_name"] for run_call in run_calls] == [
        "iPhone 14 Plus",
        "iPad Pro 13-inch (M5)",
        "iPhone 14 Plus",
        "iPad Pro 13-inch (M5)",
    ]
    assert all(
        run_call[1]["only_testing"] == "PlaniniUITests/PlaniniUITests/testMarketingScreenshots"
        for run_call in run_calls
    )
    assert all(run_call[1]["attempts"] == 2 for run_call in run_calls)
    assert [
        (run_call[1]["expected_width"], run_call[1]["expected_height"]) for run_call in run_calls
    ] == [(1284, 2778), (2064, 2752), (1284, 2778), (2064, 2752)]
    watch_calls = [call[1] for call in calls if call[0] == "watch"]
    assert watch_calls == [
        {
            "base_url": "http://localhost:8019",
            "bootstrap_email": "planini@schaedler.rocks",
            "initial_list_name": "Weekly groceries",
            "language": "en",
            "locale": "en-US",
            "artifact_dir": "e2e-artifacts/ios-marketing-screenshots/watchos/en-US",
            "phone_device": "iPhone 17 Pro",
            "watch_device": "Apple Watch Ultra 3 (49mm)",
        },
        {
            "base_url": "http://localhost:8019",
            "bootstrap_email": "planini-de@schaedler.rocks",
            "initial_list_name": "Wocheneinkauf",
            "language": "de",
            "locale": "de-DE",
            "artifact_dir": "e2e-artifacts/ios-marketing-screenshots/watchos/de-DE",
            "phone_device": "iPhone 17 Pro",
            "watch_device": "Apple Watch Ultra 3 (49mm)",
        },
    ]
    assert len([call for call in calls if call[0] == "shutdown"]) == 6
    assert calls[-1] == ("stop", {"pid_path": "ios-marketing-screenshots-server.pid"})


def test_check_ios_ci_runs_only_mac_native_e2e_prerequisites() -> None:
    assert [pre.body.__name__ for pre in tasks.check_ios_ci.pre] == [
        "install_xcodegen",
        "check_ios_e2e",
        "check_ios_ui_e2e",
        "check_ios_marketing_screenshots",
    ]


def test_install_deps_runs_python_and_js_bootstrap(monkeypatch) -> None:
    calls: list[tuple[str, object]] = []

    monkeypatch.setattr(
        tasks.setup_venv,
        "body",
        lambda c, python_bin="python3.14": calls.append(("setup_venv", python_bin)),
    )
    monkeypatch.setattr(
        tasks.install_js,
        "body",
        lambda c: calls.append(("install_js", None)),
    )
    monkeypatch.setattr(
        tasks.install_browser,
        "body",
        lambda c, with_deps=False: calls.append(("install_browser", with_deps)),
    )

    tasks.install_deps.body(
        None,
        python_bin="python3.13",
        with_browser=True,
        browser_with_deps=True,
    )

    assert calls == [
        ("setup_venv", "python3.13"),
        ("install_js", None),
        ("install_browser", True),
    ]
