#!/usr/bin/env python3
"""Renew the expiration date of the fake provisioning profiles.

The profiles shipped in build-system/fake-codesigning expired on 2026-10-30,
which makes rules_apple reject the build.  We rewrite the embedded plist with a
future ExpirationDate and re-sign the CMS container with the fake certificate
that was imported into temp.keychain by ImportCertificates.py.
"""

import datetime
import glob
import os
import plistlib
import subprocess
import sys
import tempfile

PROFILE_DIR = "build-system/fake-codesigning/profiles"
KEYCHAIN = "temp.keychain"
EXPIRATION = datetime.datetime(2036, 1, 1, 0, 0, 0)


def run(args, check=True):
    return subprocess.run(args, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def signing_identity():
    result = run(["security", "find-identity", "-v", "-p", "codesigning", KEYCHAIN])
    output = result.stdout.decode("utf-8", "replace")
    for line in output.splitlines():
        if '"' in line:
            return line.split('"')[1]
    raise SystemExit("No codesigning identity found in {}:\n{}".format(KEYCHAIN, output))


def renew_profile(path, identity):
    profile_data = run(["security", "cms", "-D", "-i", path]).stdout
    info = plistlib.loads(profile_data)
    old_expiration = info.get("ExpirationDate")
    info["ExpirationDate"] = EXPIRATION
    info.pop("DER-Encoded-Profile", None)

    file_descriptor, temp_path = tempfile.mkstemp(suffix=".plist")
    try:
        with os.fdopen(file_descriptor, "wb") as temp_file:
            temp_file.write(plistlib.dumps(info))
        run(["security", "cms", "-S", "-k", KEYCHAIN, "-N", identity, "-i", temp_path, "-o", path])
    finally:
        os.unlink(temp_path)

    # Make sure the freshly signed profile can still be decoded.
    check = plistlib.loads(run(["security", "cms", "-D", "-i", path]).stdout)
    assert check["ExpirationDate"] == EXPIRATION
    print("{}: {} -> {}".format(os.path.basename(path), old_expiration, check["ExpirationDate"]))


def main():
    profiles = sorted(glob.glob(os.path.join(PROFILE_DIR, "*.mobileprovision")))
    if not profiles:
        raise SystemExit("No provisioning profiles found in {}".format(PROFILE_DIR))

    identity = signing_identity()
    print("Using signing identity: {}".format(identity))
    for path in profiles:
        renew_profile(path, identity)
    print("Renewed {} provisioning profiles".format(len(profiles)))


if __name__ == "__main__":
    sys.exit(main())
