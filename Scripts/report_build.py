#!/usr/bin/env python3
"""Turn compiler/test errors and project warnings in CI logs into GitHub annotations."""
import pathlib
import re
import sys

logs = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/logs")
pattern = re.compile(r"^(?:.*?/)?((?:Sources|Tests|Backend)/[^:]+):(\d+):(?:(\d+):)? (error|warning): (.*)$")
seen, errors, warnings = set(), 0, 0
for log in sorted(logs.glob("*.log")):
    for line in log.read_text(errors="replace").splitlines():
        match = pattern.match(line.strip())
        if match:
            path, row, col, kind, message = match.groups()
            key = (path, row, kind, message)
            if key in seen:
                continue
            seen.add(key)
            if kind == "error":
                errors += 1
            else:
                warnings += 1
            if (kind == "error" and errors <= 40) or (kind == "warning" and warnings <= 25):
                print(f"::{kind} file={path},line={row},col={col or 1}::{message}")
        elif re.search(r"(error:|\*\* BUILD FAILED|failed \(|✘|not ok )", line) and len(line) < 400:
            key = ("raw", line.strip())
            if key not in seen and errors < 40:
                seen.add(key)
                errors += 1
                print(f"::error title={log.stem}::{line.strip()}")
print(f"::notice title=Build report::{errors} error lines, {warnings} project warnings")
