#!/bin/bash
set -euo pipefail

task_root="${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
cd "$task_root"

test -f AtendeBem.xcodeproj/project.pbxproj
test -f Packages/AtendeBemKit/Package.swift
test -f Config/App.xcconfig

# The package is committed beside the project; no private web checkout is needed.
xcodebuild -version
swift --version
python3 -m unittest discover -s scripts -p 'test_*.py'
bash scripts/test-local.sh
