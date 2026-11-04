.PHONY: test test-swift test-js lint-pbxproj

test: lint-pbxproj check-release-ads check-launch test-swift test-js

lint-pbxproj:
	python3 scripts/lint_pbxproj.py

check-release-ads:
	python3 scripts/check_release_ads.py

typecheck:
	sh scripts/typecheck_app.sh

check-launch:
	python3 scripts/launch_mark.py --check

test-swift:
	swift test

test-js:
	npm --prefix js-tests install
	npm --prefix js-tests test
