from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def run_with_live_summary(
    command: list[str],
    *,
    label: str,
    log_file: Path,
    progress_lines: int,
) -> int:
    log_file.parent.mkdir(parents=True, exist_ok=True)
    print(f"[{label}] started", flush=True)

    with log_file.open("w", encoding="utf-8", buffering=1) as full_log:
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except OSError as exc:
            print(f"[{label}] could not start: {exc}", file=sys.stderr, flush=True)
            return 127

        assert process.stdout is not None
        line_count = 0
        for line in process.stdout:
            full_log.write(line)
            full_log.flush()
            line_count += 1
            if line_count % progress_lines == 0:
                print(f"[{label}] still running ({line_count} output lines captured)", flush=True)

        exit_code = process.wait()

    if exit_code == 0:
        print(f"[{label}] completed successfully ({line_count} output lines captured)", flush=True)
        return 0

    print(
        f"[{label}] failed with exit code {exit_code}; full output follows",
        file=sys.stderr,
        flush=True,
    )
    with log_file.open(encoding="utf-8", errors="replace") as full_log:
        for line in full_log:
            print(line, end="", flush=True)
    return exit_code


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stream concise live progress while retaining full command output for failures."
    )
    parser.add_argument(
        "--label", required=True, help="Short operation name used in progress output."
    )
    parser.add_argument(
        "--log-file", required=True, type=Path, help="Path for complete command output."
    )
    parser.add_argument(
        "--progress-lines",
        type=int,
        default=200,
        help="Print one live progress update after this many command output lines.",
    )
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command to run after --.")
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    if args.progress_lines < 1:
        parser.error("--progress-lines must be at least 1")
    return args


def main() -> None:
    args = parse_args()
    raise SystemExit(
        run_with_live_summary(
            args.command,
            label=args.label,
            log_file=args.log_file,
            progress_lines=args.progress_lines,
        )
    )


if __name__ == "__main__":
    main()
