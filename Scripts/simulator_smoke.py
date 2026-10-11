#!/usr/bin/env python3
"""Install/launch the actual companion app and capture a simulator screenshot."""
import json
import pathlib
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[1]
def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode != 0:
        # Surface the simulator's own message as a GitHub annotation.
        message = (result.stderr or result.stdout).strip().replace("\n", " | ")[:900]
        print(f"::error title=simctl {args[2] if len(args) > 2 else ''}::{message}")
        raise SystemExit(result.returncode)
    return result.stdout.strip()
data = json.loads(run("xcrun", "simctl", "list", "--json"))
runtimes = [r for r in data["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]]
runtime = sorted(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))[-1]
device_type = next(d for d in data["devicetypes"] if "iPhone 16 Pro" == d["name"])
device = run("xcrun", "simctl", "create", "WianTribe Keyboard QA", device_type["identifier"], runtime["identifier"])
try:
    run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b")
    app = root / "build/simulator/Build/Products/Debug-iphonesimulator/WianTribeKeyboard.app"
    run("xcrun", "simctl", "install", device, str(app))
    run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
    print(run("xcrun", "simctl", "launch", device, "com.wiantribe.keyboard"))
    time.sleep(12)  # Let one-time simulator setup notification banners disappear.
    output = root / "build/output"
    output.mkdir(parents=True, exist_ok=True)
    run("xcrun", "simctl", "io", device, "screenshot", str(output / "Home-iPhone.png"))
    print("Companion app installed and launched in iPhone simulator")
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
    subprocess.run(["xcrun", "simctl", "delete", device], check=False)
