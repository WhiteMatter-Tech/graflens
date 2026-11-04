#!/bin/sh
# Verify the actual app loads every fixture panel without any scroll interaction.
# Build the Debug simulator app first; optionally set APP_PATH and SIMULATOR_ID.
set -eu
cd "$(dirname "$0")/.."
APP_PATH=${APP_PATH:-build/V2Derived/Build/Products/Debug-iphonesimulator/GrafLens.app}
SIMULATOR_ID=${SIMULATOR_ID:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["state"] == "Booted"))')}
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
python3 Tests/panel_cache_fixture.py > "$TEST_DIR/fixture.log" 2>&1 &
FIXTURE_PID=$!
xcrun simctl terminate "$SIMULATOR_ID" tech.whitematter.graflens >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
kill -0 "$FIXTURE_PID" || { cat "$TEST_DIR/fixture.log"; exit 1; }
xcrun simctl launch "$SIMULATOR_ID" tech.whitematter.graflens --fixture-server http://127.0.0.1:18765 --fixture-dashboard
python3 - <<'PY'
import json, sys, time
from urllib.request import urlopen
sys.path.insert(0, 'Tests')
from fixture_server import PANELS
native = sum(p['type'] in ('timeseries', 'stat', 'gauge') for p in PANELS)
web = sum(p['type'] not in ('timeseries', 'stat', 'gauge', 'row') for p in PANELS)
def counts():
    with urlopen('http://127.0.0.1:18765/cache-counts', timeout=5) as response:
        return json.load(response)
for _ in range(60):
    actual = counts()
    if actual['queries'] >= native and actual['pages'] >= web and actual['activeQueries'] == 0:
        break
    time.sleep(0.5)
assert actual['queries'] == native, f'Expected {native} native panels without scrolling: {actual}'
assert actual['pages'] == web, f'Expected {web} embedded panels without scrolling: {actual}'
assert actual['peakQueries'] > 1, f'Expected concurrent native requests: {actual}'
time.sleep(2)
assert counts() == actual, f'Panels unexpectedly reloaded: {actual} -> {counts()}'
print(f'PASS: All {native} native panels and {web} embedded panel loaded without scrolling.')
print(f'PASS: Native requests overlapped ({actual["peakQueries"]} active at once).')
print('PASS: No duplicate requests after the dashboard settled.')
PY
