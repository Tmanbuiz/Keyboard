#!/usr/bin/env python3
"""Allow explicitly requested UI-only checks when production inputs are unchanged."""
import json
import os
import pathlib
import re
import subprocess

event = json.loads(pathlib.Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
before = event.get("before", "")
message = (event.get("head_commit") or {}).get("message", "")
allowed = {".github/workflows/ios.yml", "Scripts/simulator_smoke.py",
           "Scripts/sign_simulator.py", "Scripts/verification_scope.py"}
ui_only = False
if "[ui-check]" in message and os.environ.get("GITHUB_REF_NAME") == "personal/background-clipboard" and re.fullmatch(r"[0-9a-f]{40}", before):
    diff = subprocess.run(["git", "diff", "--name-only", before], text=True, capture_output=True)
    paths = diff.stdout.splitlines()
    ui_only = diff.returncode == 0 and bool(paths) and all(path in allowed or path.startswith("Tests/KeyboardUITests/") for path in paths)
with pathlib.Path(os.environ["GITHUB_OUTPUT"]).open("a") as stream:
    stream.write("full_check=" + ("false" if ui_only else "true") + "\n")
print("Checking simulator signing and UI flow." if ui_only else "Checking unit tests, device package and simulator UI.")
