import subprocess
import sys
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "run_live_summary.py"


def run_summary(tmp_path: Path, label: str, code: str, *, progress_lines: int = 2):
    log_file = tmp_path / "full.log"
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT_PATH),
            "--label",
            label,
            "--log-file",
            str(log_file),
            "--progress-lines",
            str(progress_lines),
            "--",
            sys.executable,
            "-c",
            code,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result, log_file


def test_live_summary_streams_brief_progress_and_keeps_full_success_log(tmp_path: Path) -> None:
    result, log_file = run_summary(
        tmp_path,
        "Archive app",
        "for number in range(1, 6): print(f'noisy line {number}', flush=True)",
    )

    assert result.returncode == 0
    assert result.stderr == ""
    assert result.stdout.splitlines() == [
        "[Archive app] started",
        "[Archive app] still running (2 output lines captured)",
        "[Archive app] still running (4 output lines captured)",
        "[Archive app] completed successfully (5 output lines captured)",
    ]
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "noisy line 1",
        "noisy line 2",
        "noisy line 3",
        "noisy line 4",
        "noisy line 5",
    ]


def test_live_summary_replays_full_output_on_failure(tmp_path: Path) -> None:
    result, log_file = run_summary(
        tmp_path,
        "Upload IPA to TestFlight",
        (
            "import sys; "
            "print('upload detail', flush=True); "
            "print('upload error', file=sys.stderr, flush=True); "
            "raise SystemExit(7)"
        ),
        progress_lines=10,
    )

    assert result.returncode == 7
    assert result.stdout == "[Upload IPA to TestFlight] started\nupload detail\nupload error\n"
    assert result.stderr == (
        "[Upload IPA to TestFlight] failed with exit code 7; full output follows\n"
    )
    assert log_file.read_text(encoding="utf-8") == "upload detail\nupload error\n"


def test_testflight_workflow_summarizes_noisy_build_and_upload_commands() -> None:
    workflow = (
        Path(__file__).resolve().parents[1]
        / ".github"
        / "workflows"
        / "ios-build-and-testflight.yml"
    ).read_text(encoding="utf-8")

    assert workflow.count("run_live_summary.py") == 4
    for label in (
        "Archive app",
        "Export App Store IPA",
        "Export ad-hoc IPA",
        "Upload IPA to TestFlight",
    ):
        assert f'--label "{label}"' in workflow
