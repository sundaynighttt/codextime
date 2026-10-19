#!/usr/bin/env python3
"""Validate only public provisioning metadata; never log the profile contents."""
import argparse
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import plistlib
import subprocess
import tempfile
import sys

TEAM = "7FCZ5TAX3B"
APP_ID = TEAM + ".com.sundaynighttt.codex-usage-monitor"
CONTAINER = "iCloud.com.sundaynighttt.codextime"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(profile_path, signed_app=None):
    result = subprocess.run(["/usr/bin/security", "cms", "-D", "-i", str(profile_path)], capture_output=True)
    require(result.returncode == 0, "Unable to decode the signed provisioning profile.")
    profile = plistlib.loads(result.stdout)
    entitlements = profile.get("Entitlements", {})
    require(profile.get("TeamIdentifier") == [TEAM], "Provisioning team does not match.")
    require(entitlements.get("com.apple.application-identifier", entitlements.get("application-identifier")) == APP_ID,
            "Provisioning app identifier does not match.")
    require(entitlements.get("com.apple.developer.team-identifier") == TEAM, "Entitlement team does not match.")
    require(CONTAINER in entitlements.get("com.apple.developer.icloud-container-identifiers", []),
            "The profile does not authorize the CloudKit container.")
    services = entitlements.get("com.apple.developer.icloud-services", [])
    require(services == "*" or "CloudKit" in services or "*" in services, "CloudKit is not enabled in the profile.")
    environment = entitlements.get("com.apple.developer.icloud-container-environment")
    require(environment == "Production" or (isinstance(environment, list) and "Production" in environment),
            "The profile does not authorize Production CloudKit.")
    require(profile.get("ProvisionsAllDevices") is True, "A Developer ID distribution profile is required.")
    require(entitlements.get("get-task-allow", entitlements.get("com.apple.security.get-task-allow", False)) is False,
            "A development debugging entitlement is not permitted for release.")
    expiration = profile.get("ExpirationDate")
    require(isinstance(expiration, datetime), "The profile has no expiration date.")
    require(expiration.replace(tzinfo=timezone.utc) > datetime.now(timezone.utc), "The profile has expired.")
    if signed_app:
        # Certificate bytes are public signing metadata, retained in a temporary directory only.
        with tempfile.TemporaryDirectory(prefix="codextime-signing-certificate-") as directory:
            prefix = str(Path(directory) / "certificate")
            result = subprocess.run(["/usr/bin/codesign", "--display", "--extract-certificates", prefix, signed_app], capture_output=True)
            require(result.returncode == 0, "Unable to inspect the signed app certificate.")
            certificate = Path(prefix + "0")
            require(certificate.is_file(), "The signed app has no signing certificate.")
            leaf_hash = hashlib.sha256(certificate.read_bytes()).digest()
            allowed_hashes = {hashlib.sha256(value).digest() for value in profile.get("DeveloperCertificates", [])}
            require(leaf_hash in allowed_hashes, "The signing certificate is not authorized by the profile.")
    print("CloudKit provisioning metadata validated: matching team, app, container, Production and Developer ID certificate.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", type=Path)
    parser.add_argument("--signed-app")
    arguments = parser.parse_args()
    try:
        validate(arguments.profile, arguments.signed_app)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        print("CloudKit provisioning validation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
