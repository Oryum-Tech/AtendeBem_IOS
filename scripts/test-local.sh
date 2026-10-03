#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_developer_dir="$(xcode-select -p)"
task_cache_root="${TMPDIR:-/private/tmp}/atendebem-swift-validation"
mkdir -p "$task_cache_root"
export CLANG_MODULE_CACHE_PATH="$task_cache_root/clang"
export SWIFT_MODULECACHE_PATH="$task_cache_root/swift-modules"

task_flags=(--disable-xctest)
# Some Command Line Tools releases ship Swift Testing as a framework but omit
# its search path and interop runtime path from the SwiftPM test runner.
if [[ -d "$task_developer_dir/Library/Developer/Frameworks/Testing.framework" ]]; then
    task_flags+=(
        -Xswiftc -F -Xswiftc "$task_developer_dir/Library/Developer/Frameworks"
        -Xlinker -rpath -Xlinker "$task_developer_dir/Library/Developer/Frameworks"
        -Xlinker -rpath -Xlinker "$task_developer_dir/Library/Developer/usr/lib"
    )
fi

swift test --package-path "$task_root/Packages/AtendeBemKit" \
    --scratch-path "$task_root/.build" \
    --cache-path "$task_cache_root/cache" \
    --config-path "$task_cache_root/config" \
    --security-path "$task_cache_root/security" \
    "${task_flags[@]}" "$@"
