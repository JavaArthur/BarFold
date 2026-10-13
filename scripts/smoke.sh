#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p verification
APP="$PWD/verification/BarFoldSmoke.app"
# A separate bundle ID keeps smoke placement preferences away from the real app.
ditto dist/BarFold.app "$APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier cn.aichanning.BarFold.Smoke' "$APP/Contents/Info.plist"
codesign --force --sign - --identifier cn.aichanning.BarFold.Smoke "$APP"
"$APP/Contents/MacOS/BarFold" --native-smoke --config "$PWD/verification/smoke-config.json" --report "$PWD/verification/native-smoke.json" > verification/native-smoke.log 2>&1 &
SMOKE_PID=$!
trap 'kill "$SMOKE_PID" 2>/dev/null || true' EXIT
for tick in {1..40}; do
    if ! kill -0 "$SMOKE_PID" 2>/dev/null; then break; fi
    sleep 1
done
if kill -0 "$SMOKE_PID" 2>/dev/null; then echo 'Native smoke timed out'; exit 1; fi
wait "$SMOKE_PID"
python3 - <<'PY'
import json
from pathlib import Path
report = json.loads(Path('verification/native-smoke.json').read_text())
for check in report['checks']:
    print(('PASS' if check['passed'] else 'FAIL') + ' ' + check['name'])
print('Native failures:', report['failed'])
raise SystemExit(0 if report['failed'] == 0 else 1)
PY
