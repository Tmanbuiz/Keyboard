#!/usr/bin/env python3
"""Verify app launch, then add/select/type with its actual keyboard in iOS."""
import json
import os
import pathlib
import plistlib
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
manifest = root / "build/simulator-device.json"
if not manifest.exists():
    subprocess.run(["python3", str(root / "Scripts/prepare_simulator.py")], check=True)
device = json.loads(manifest.read_text())["device"]
try:
    run("xcrun", "simctl", "bootstatus", device, "-b")
    app = root / "build/simulator/Build/Products/Debug-iphonesimulator/WianTribeKeyboard.app"
    subprocess.run(["codesign", "-d", "--entitlements", "-", str(app)], check=False)
    run("xcrun", "simctl", "install", device, str(app))
    run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
    bundle_id = plistlib.loads((app / "Info.plist").read_bytes())["CFBundleIdentifier"]
    for attempt in range(3):
        launch = subprocess.run(["xcrun", "simctl", "launch", device, bundle_id], text=True, capture_output=True)
        if launch.returncode == 0:
            launched = launch.stdout.strip()
            break
        print(launch.stderr.strip(), flush=True)
        if attempt < 2: time.sleep(4)
    else:
        diagnostic = subprocess.run(["xcrun", "simctl", "spawn", device, "log", "show", "--style", "compact", "--last", "2m",
            "--predicate", 'process == "SpringBoard" OR process == "runningboardd"'], text=True, capture_output=True)
        (root / "build/logs/simulator-launch.log").write_text(diagnostic.stdout + diagnostic.stderr)
        print(diagnostic.stdout[-5000:])
        raise SystemExit("Simulator launch failed; see simulator-launch.log")
    print(launched)
    pid = int(launched.rsplit(":", 1)[-1].strip())
    time.sleep(12)  # Let one-time simulator setup notification banners disappear.
    try:
        os.kill(pid, 0)  # Signal 0 checks the launched app is still alive.
    except ProcessLookupError:
        raise SystemExit("The companion app exited after launch")
    output = root / "build/output"
    output.mkdir(parents=True, exist_ok=True)
    run("xcrun", "simctl", "io", device, "screenshot", str(output / "Home-iPhone.png"))
    print("Companion app installed and launched in iPhone simulator", flush=True)
    log = root / "build/logs/keyboard-ui.log"
    verification = root / "build/verification"
    verification.mkdir(parents=True, exist_ok=True)
    with log.open("w") as stream:
        tests = subprocess.run([
            "xcodebuild", "test-without-building", "-project", str(root / "WianTribeKeyboard.xcodeproj"),
            "-scheme", "WianTribeKeyboard", "-configuration", "Debug", "-destination", f"id={device}",
            "-derivedDataPath", str(root / "build/simulator"), "-resultBundlePath", str(verification / "KeyboardRegistration.xcresult"),
            "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "ENTITLEMENTS_REQUIRED=YES",
            "-only-testing:WianTribeKeyboardUITests/KeyboardRegistrationTests/testKeyboardCanBeAddedSelectedAndType"
        ], stdout=stream, stderr=subprocess.STDOUT, timeout=480)
    test_log = log.read_text()
    print(test_log[-10000:])
    for line in test_log.splitlines():
        if "error:" in line or "XCTAssert" in line or "Test Case" in line:
            print(line)
    exported = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(verification / "KeyboardRegistration.xcresult"),
        "--output-path", str(verification / "screenshots")], check=False, text=True, capture_output=True)
    if exported.returncode:
        print("Screenshot export was unavailable: " + exported.stderr[-800:])
    if tests.returncode:
        raise SystemExit("Keyboard registration/typing UI test failed; see keyboard-ui.log and xcresult")
    print("Actual keyboard registered, typed, selected Groq, and reviewed/edited/replaced its test result")
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
    subprocess.run(["xcrun", "simctl", "delete", device], check=False)
