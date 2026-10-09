#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc GrafLens/Models/GrafanaModels.swift GrafLens/Models/NativePanelData.swift GrafLens/Services/GrafanaAPIClient.swift Tests/RegressionTests.swift -o "$TEST_DIR/regressions"
"$TEST_DIR/regressions"
