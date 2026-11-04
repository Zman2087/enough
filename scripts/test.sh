#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/lint_pbxproj.py
python3 scripts/check_release_ads.py
python3 scripts/launch_mark.py --check
swift test
npm --prefix js-tests install
npm --prefix js-tests test
