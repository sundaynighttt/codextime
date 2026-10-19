#!/usr/bin/env python3
"""Keep iCloud target attributes typed when XcodeGen serializes nested attributes as strings."""
import json
from pathlib import Path
import re
import subprocess

project = Path(__file__).resolve().parents[1] / "CodexTime.xcodeproj/project.pbxproj"


def capabilities():
    result = subprocess.run(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project)], check=True, capture_output=True)
    data = json.loads(result.stdout)
    objects = data["objects"]
    attributes = objects[data["rootObject"]]["attributes"]["TargetAttributes"]
    return [attributes[key].get("SystemCapabilities") for key, value in objects.items()
            if value.get("isa") == "PBXNativeTarget" and value.get("name") in ["CodexTime", "CodexTimeWidgetExtension"]]


values = capabilities()
if len(values) != 2:
    raise SystemExit("Expected the iPhone app and widget targets.")
if all(isinstance(value, dict) and str(value.get("com.apple.iCloud", {}).get("enabled")) == "1" for value in values):
    raise SystemExit(0)
if not all(isinstance(value, str) and "com.apple.iCloud" in value for value in values):
    raise SystemExit("Unexpected iCloud target attribute shape; refusing to rewrite the project.")
source = project.read_text()
pattern = re.compile(r'(?m)^(\t+)SystemCapabilities = "(?:\\.|[^"\\])*";$')
matches = list(pattern.finditer(source))
if len(matches) != 2 or not all("com.apple.iCloud" in match.group() for match in matches):
    raise SystemExit("Unexpected SystemCapabilities serialization; refusing to rewrite the project.")


def dictionary(match):
    indent = match.group(1)
    return (indent + "SystemCapabilities = {\n" + indent + "\tcom.apple.iCloud = {\n"
            + indent + "\t\tenabled = 1;\n" + indent + "\t};\n" + indent + "};")

project.write_text(pattern.sub(dictionary, source))
if not all(isinstance(value, dict) and str(value.get("com.apple.iCloud", {}).get("enabled")) == "1" for value in capabilities()):
    raise SystemExit("iCloud target attributes did not validate.")
