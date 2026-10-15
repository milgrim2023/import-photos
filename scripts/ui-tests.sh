#!/bin/bash
# Runs the XCUITest smoke suite (UITests/) against the Debug app in its test mode.
# Needs an unlocked, logged-in desktop session (the tests really click). ~1 minute.
# Usage: scripts/ui-tests.sh [TestClass/testName]   e.g. scripts/ui-tests.sh PhotoImportUITests/testSortMenuReordersTheGrid
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
ONLY=${1:+-only-testing:PhotoImportUITests/$1}
xcodebuild test -project PhotoImport.xcodeproj -scheme PhotoImport -destination 'platform=macOS' \
  -derivedDataPath build/ui-tests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ${ONLY:-} 2>&1 \
  | grep -E "Test Case .* (passed|failed)|error:|Executed .* tests|TEST (SUCCEEDED|FAILED)" | sed 's/^.*PhotoImportUITests\.//'
