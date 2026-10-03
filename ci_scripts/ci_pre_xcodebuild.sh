#!/bin/bash
set -euo pipefail

# Apple restores compiled test products on simulator workers without a source
# checkout. Version preparation belongs to build-for-testing, never test execution.
if [[ "${CI_XCODEBUILD_ACTION:-}" == "test-without-building" ]]; then
    echo "Using previously compiled test products; no source version changes."
    exit 0
fi

# Xcode Cloud's build sequence is separate from local Transporter builds.
# Reserve a range above the existing local builds without changing marketing version.
case "${CI_BUILD_NUMBER:-}" in
    ''|*[!0-9]*) echo "A numeric CI_BUILD_NUMBER is required." >&2; exit 1 ;;
esac
task_root="${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
python3 - "$task_root/Config/App.xcconfig" "$CI_BUILD_NUMBER" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
sequence = int(sys.argv[2])
if not 1 <= sequence <= 89999:
    raise SystemExit("Cloud build sequence outside reserved range")
text = path.read_text(encoding="utf-8")
text, count = re.subn(r"(?m)^CURRENT_PROJECT_VERSION\s*=\s*\d+\s*$",
                      f"CURRENT_PROJECT_VERSION = {10000 + sequence}", text)
if count != 1:
    raise SystemExit("Expected one CURRENT_PROJECT_VERSION setting")
path.write_text(text, encoding="utf-8")
print(f"Cloud build number: {10000 + sequence}")
PY
