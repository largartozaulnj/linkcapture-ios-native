#!/usr/bin/env python3
"""Inventory real installed simulator runtimes. Never invent coverage."""
import json
import os
import re
import subprocess
from pathlib import Path

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
requested = os.environ.get("REQUESTED_IOS", "")
full = os.environ.get("FULL_DEVICE_MATRIX", "false") == "true"
output = Path("build/compatibility")
output.mkdir(parents=True, exist_ok=True)
devices = []
for runtime, values in data["devices"].items():
    match = re.search(r"iOS-(\d+)", runtime)
    if not match or requested and match[1] != requested:
        continue
    for device in values:
        if re.fullmatch(r"iPhone (?:14|15|16|17)(?: Plus| Pro| Pro Max|e)?|iPhone Air", device["name"]):
            devices.append({**device, "runtime": runtime})
(output / "installed-matching-devices.json").write_text(json.dumps(devices, indent=2))
if not devices:
    result = f"iOS {requested}: NÃO EXECUTADO — runtime/modelos não disponíveis neste runner. Teste físico ou outro Mac ainda necessário."
    print(result)
    (output / "NOT-TESTED.txt").write_text(result)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as file:
            file.write(result + "\n")
    raise SystemExit(0)

if not full:
    selected = [devices[0], devices[-1]] if len(devices) > 1 else devices
else:
    selected = devices
failed = []
for device in selected:
    label = re.sub(r"[^a-zA-Z0-9-]", "-", device["name"])
    bundle = output / f"{device['runtime']}-{label}.xcresult"
    command = ["xcodebuild", "-project", "LinkCapture.xcodeproj", "-scheme", "LinkCapture",
               "-destination", f"platform=iOS Simulator,id={device['udid']}", "-derivedDataPath", "build/compatibility-derived",
               "-resultBundlePath", str(bundle), "-only-testing:LinkCaptureTests/PolicyTests", "-only-testing:LinkCaptureTests/CompatibilityTests", "CODE_SIGNING_ALLOWED=NO", "test"]
    result = subprocess.run(command)
    if result.returncode:
        failed.append(device)
(output / "execution.json").write_text(json.dumps({"selected": selected, "failed": failed, "network": "NOT TESTED by this job", "physicalDevices": "NOT TESTED"}, indent=2))
raise SystemExit(1 if failed else 0)

