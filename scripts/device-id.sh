#!/usr/bin/env bash
# 接続中（ペアリング済み）の iPhone の devicectl 識別子を 1 つ返す。
# MOBILE_IDE_DEVICE が設定されていればそれを優先する。
set -euo pipefail
if [ -n "${MOBILE_IDE_DEVICE:-}" ]; then
  echo "$MOBILE_IDE_DEVICE"
  exit 0
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
JSON="$(mktemp -t mobile-ide-devices).json"
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
python3 - "$JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    conn = d.get("connectionProperties", {})
    hw = d.get("hardwareProperties", {})
    if conn.get("pairingState") == "paired" and hw.get("platform") == "iOS":
        print(d["identifier"]); sys.exit(0)
sys.stderr.write("ペアリング済みの iPhone が見つかりません。USB で接続して信頼してください。\n")
sys.exit(1)
PY
