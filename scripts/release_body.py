#!/usr/bin/env python3
"""Assemble the GitHub release body from CHANGELOG.md and CHANGELOG.id.md.

Usage: python3 scripts/release_body.py <version> <output-file>

The changelog files hold the version sections. This script takes the section
for <version> from each file, adds the fixed Install / Update blocks (which
must match README Installation, Option A) and writes the combined body to
<output-file>. No release notes text lives in the workflow itself.
"""
import re
import sys


def read_section(path: str, version: str) -> str:
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    match = re.search(
        r"^## v" + re.escape(version) + r"[^\n]*\n(.*?)(?=^## v|^## (Earlier|Rilis)|\Z)",
        text,
        re.S | re.M,
    )
    if not match:
        sys.exit(f"No section for v{version} in {path}")
    return match.group(1).strip()


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    version, output_file = sys.argv[1], sys.argv[2]

    en = read_section("CHANGELOG.md", version)
    idn = read_section("CHANGELOG.id.md", version)

    english = f"""# English

{en}

## Install / Update

Download the APK matching your device from Assets below (`app-arm64-v8a-release.apk` for most modern phones, `app-armeabi-v7a-release.apk` for older 32-bit ones), open it and follow the prompts. Requires Android 8.0 (API 26).
"""

    indonesian = f"""# Bahasa Indonesia

{idn}

## Instalasi / Update

Download APK sesuai HPmu dari Assets di bawah (`app-arm64-v8a-release.apk` untuk kebanyakan HP modern, `app-armeabi-v7a-release.apk` untuk yang 32-bit lama), buka, lalu ikuti petunjuknya. Membutuhkan Android 8.0 (API 26).
"""

    body = english + "\n<br>\n\n---\n\n<br>\n\n" + indonesian
    with open(output_file, "w", encoding="utf-8") as handle:
        handle.write(body)


if __name__ == "__main__":
    main()
