#!/bin/sh
# Build the Debug simulator app first. Exercises 76 viewport-sensitive embeds.
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
python3 Tests/web_panel_stress_fixture.py > "$TEST_DIR/fixture.log" 2>&1 &
FIXTURE_PID=$!
xcrun simctl terminate "$SIMULATOR_ID" tech.whitematter.graflens >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
kill -0 "$FIXTURE_PID" || { cat "$TEST_DIR/fixture.log"; exit 1; }
xcrun simctl launch "$SIMULATOR_ID" tech.whitematter.graflens --fixture-server http://127.0.0.1:18767 --fixture-dashboard
python3 - <<'PY'
import json, time
from urllib.request import urlopen

def read(path):
    with urlopen('http://127.0.0.1:18767/' + path, timeout=5) as response:
        return json.load(response)
for _ in range(90):
    measurements = read('measurements')
    if len(measurements) == 76 and all(any(r['painted'] for r in reports) for reports in measurements.values()):
        break
    time.sleep(0.5)
assert len(measurements) == 76, f'Only {len(measurements)} panels reported without scrolling'
assert all(all(r['width'] > 0 and r['height'] > 0 and r['painted'] for r in reports) for reports in measurements.values()), 'An embed started without a usable viewport'
assert all(all(r['innerWidth'] > 0 and r['innerHeight'] > 0 for r in reports) for reports in measurements.values()), 'An embed has an empty browser viewport'
expected = {str(i): 1 for i in range(1, 77)}
assert read('page-counts') == expected, 'Unexpected duplicate or missing navigations'
# Wait beyond the readiness timeout: normal pages must never trigger recovery.
time.sleep(32)
assert read('page-counts') == expected, 'A rendered panel unnecessarily retried'
print('PASS: All 76 embedded panels rendered at a positive viewport size without scrolling.')
print('PASS: Each panel loaded exactly once, including after the readiness timeout.')
PY
