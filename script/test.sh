#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"
# Run serially: ToolGitClientTests exercise real git, and process spawns
# on shared CI runners are slow enough to starve timing-sensitive
# main-actor tests running in parallel.
ANVIL_RUNNING_TESTS=1 swift test --no-parallel "$@"
