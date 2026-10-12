#!/usr/bin/env python3
"""Start the isolated UI-test simulator while independent compilation runs."""
import json
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]

def run(*args):
    return subprocess.check_output(args, text=True).strip()

data = json.loads(run("xcrun", "simctl", "list", "--json"))
subprocess.run(["defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "false"], check=True)
runtimes = [item for item in data["runtimes"] if item.get("isAvailable") and "iOS" in item["name"]]
runtime = max(runtimes, key=lambda item: tuple(map(int, item["version"].split("."))))
device_type = next(item for item in data["devicetypes"] if item["name"] == "iPhone 16 Pro")
device = run("xcrun", "simctl", "create", "WianTribe Keyboard QA", device_type["identifier"], runtime["identifier"])
manifest = root / "build/simulator-device.json"
manifest.parent.mkdir(parents=True, exist_ok=True)
manifest.write_text(json.dumps({"device": device}))
subprocess.run(["xcrun", "simctl", "boot", device], check=True)
print("Started the isolated iPhone simulator; UI checks will wait for boot readiness.", flush=True)
