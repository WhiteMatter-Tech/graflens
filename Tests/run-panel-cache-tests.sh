#!/bin/sh
# Requires a booted iOS Simulator. Set SIMULATOR_ID to choose one explicitly.
set -eu
cd "$(dirname "$0")/.."
SIMULATOR_ID=${SIMULATOR_ID:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["state"] == "Booted"))')}
TEST_DIR=$(mktemp -d)
FIXTURE_PID=""
cleanup() {
    if [ -n "$FIXTURE_PID" ]; then
        kill "$FIXTURE_PID" 2>/dev/null || true
        wait "$FIXTURE_PID" 2>/dev/null || true
    fi
    xcrun simctl terminate "$SIMULATOR_ID" tech.whitematter.graflens.cache-tests >/dev/null 2>&1 || true
    xcrun simctl uninstall "$SIMULATOR_ID" tech.whitematter.graflens.cache-tests >/dev/null 2>&1 || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT
python3 Tests/panel_cache_fixture.py > "$TEST_DIR/fixture.log" 2>&1 &
FIXTURE_PID=$!
APP="$TEST_DIR/PanelCacheTests.app"
mkdir -p "$APP"
python3 - "$APP/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({"CFBundleExecutable":"PanelCacheTests", "CFBundleIdentifier":"tech.whitematter.graflens.cache-tests",
        "CFBundleName":"Panel Cache Tests", "CFBundlePackageType":"APPL", "CFBundleVersion":"1",
        "CFBundleShortVersionString":"1.0", "MinimumOSVersion":"17.0", "LSRequiresIPhoneOS":True,
        "UIDeviceFamily":[1,2], "UILaunchScreen":{}, "UIApplicationSceneManifest":{"UIApplicationSupportsMultipleScenes":False}, "NSAppTransportSecurity":{"NSAllowsLocalNetworking":True}}, f)
PY
xcrun --sdk iphonesimulator swiftc -parse-as-library -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -target "$(uname -m)-apple-ios17.0-simulator" \
    GrafLens/Models/GrafanaModels.swift GrafLens/Models/NativePanelData.swift \
    GrafLens/Services/GrafanaAPIClient.swift GrafLens/Services/WebAuthManager.swift \
    GrafLens/Services/PanelSessionCache.swift Tests/PanelCacheIntegrationTests.swift \
    -o "$APP/PanelCacheTests"
kill -0 "$FIXTURE_PID" || { cat "$TEST_DIR/fixture.log"; exit 1; }
xcrun simctl install "$SIMULATOR_ID" "$APP"
xcrun simctl launch "$SIMULATOR_ID" tech.whitematter.graflens.cache-tests
DATA_DIR=$(xcrun simctl get_app_container "$SIMULATOR_ID" tech.whitematter.graflens.cache-tests data)
for attempt in $(seq 1 60); do
    if [ -f "$DATA_DIR/Documents/results.txt" ]; then
        cat "$DATA_DIR/Documents/results.txt"
        rg -q '^PASS: [0-9]+ panel cache integration checks$' "$DATA_DIR/Documents/results.txt"
        exit $?
    fi
    sleep 1
done
cat "$TEST_DIR/fixture.log"
echo "Timed out waiting for panel cache tests"
exit 1
