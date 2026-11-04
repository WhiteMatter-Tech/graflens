#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
FIXTURE_PID=""
cleanup() {
    if [ -n "$FIXTURE_PID" ]; then
        kill "$FIXTURE_PID" 2>/dev/null || true
        wait "$FIXTURE_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT
python3 Tests/auth_error_fixture.py > "$TEST_DIR/fixture.log" 2>&1 &
FIXTURE_PID=$!
swiftc GrafLens/Models/GrafanaModels.swift GrafLens/Models/NativePanelData.swift \
    GrafLens/Services/GrafanaAPIClient.swift Tests/AuthErrorIntegrationTests.swift -o "$TEST_DIR/auth-errors"
kill -0 "$FIXTURE_PID" || { cat "$TEST_DIR/fixture.log"; exit 1; }
"$TEST_DIR/auth-errors"
