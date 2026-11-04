#!/usr/bin/env python3
"""Fail if the Release / App Store build can hide sponsored posts.

PERSONAL_BUILD may appear only on the Personal configuration and the
Enough Personal scheme. The Enough scheme's Release archive must not.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lint_pbxproj import parse_pbxproj

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROJECT = os.path.join(ROOT, "Enough.xcodeproj", "project.pbxproj")
MAIN_SCHEME = os.path.join(ROOT, "Enough.xcodeproj", "xcshareddata", "xcschemes", "Enough.xcscheme")
PERSONAL_SCHEME = os.path.join(ROOT, "Enough.xcodeproj", "xcshareddata", "xcschemes", "Enough Personal.xcscheme")


def release_mentions_personal(config):
    if config.get("name") != "Release":
        return False
    return "PERSONAL_BUILD" in repr(config.get("buildSettings", {}))


def walk_configs(objects):
    releases = []
    personals = []
    for obj in objects.values():
        if not isinstance(obj, dict) or obj.get("isa") != "XCBuildConfiguration":
            continue
        if obj.get("name") == "Release":
            releases.append(obj)
        elif obj.get("name") == "Personal":
            personals.append(obj)
    return releases, personals


def check_project(text):
    root = parse_pbxproj(text)
    objects = root["objects"]
    releases, personals = walk_configs(objects)
    if not releases:
        raise SystemExit("no Release configuration found")
    for config in releases:
        if release_mentions_personal(config):
            raise SystemExit("Release build settings enable PERSONAL_BUILD; ad hiding must stay off")
    if not personals:
        raise SystemExit("Personal configuration is missing")
    if not any("PERSONAL_BUILD" in repr(config.get("buildSettings", {})) for config in personals):
        raise SystemExit("Personal configuration does not define PERSONAL_BUILD")
    enabled = [config for config in personals if "PERSONAL_BUILD" in repr(config.get("buildSettings", {}))]
    # The flag belongs on the project-level Personal config only, not copied onto Release.
    if len(enabled) != 1:
        raise SystemExit(f"expected one Personal configuration to define PERSONAL_BUILD, found {len(enabled)}")


def check_schemes():
    main = open(MAIN_SCHEME, encoding="utf-8").read()
    personal = open(PERSONAL_SCHEME, encoding="utf-8").read()
    if 'buildConfiguration = "Personal"' in main:
        raise SystemExit("the Enough scheme must not use the Personal configuration")
    if 'ArchiveAction' not in main or 'buildConfiguration = "Release"' not in main:
        raise SystemExit("the Enough scheme must archive with Release")
    if 'LaunchAction' not in main or main.count('buildConfiguration = "Debug"') < 1:
        raise SystemExit("the Enough scheme must still launch with Debug")
    if 'buildConfiguration = "Personal"' not in personal:
        raise SystemExit("Enough Personal must build with the Personal configuration")
    if 'buildConfiguration = "Release"' in personal:
        raise SystemExit("Enough Personal must not archive or profile as Release")


def self_test():
    bad = {"name": "Release", "buildSettings": {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "PERSONAL_BUILD"}}
    good = {"name": "Release", "buildSettings": {"SWIFT_COMPILATION_MODE": "wholemodule"}}
    if not release_mentions_personal(bad) or release_mentions_personal(good):
        raise SystemExit("self-test: Release PERSONAL_BUILD detection failed")


def main():
    self_test()
    check_project(open(PROJECT, encoding="utf-8").read())
    check_schemes()
    print("Release does not enable PERSONAL_BUILD; Enough Personal does")


if __name__ == "__main__":
    main()
