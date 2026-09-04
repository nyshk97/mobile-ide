"""アプリを --console 付きで起動し、stdout の目印行（SPIKE / TERMINAL で始まる行）を集める自走ドライバ。

使い方:
  python3 scripts/console-run.py [--device ID] [--env KEY=VALUE ...] [--until MARKER] [--timeout SEC] [--keep]
  --device を付けると devicectl（実機）、無ければ simctl（シミュレータ）。
  --env はアプリの環境変数（SIMCTL_CHILD_ / DEVICECTL_CHILD_ のプレフィックスはスクリプトが付ける）。
  --until の目印行が出たら終了（既定: 最初の目印行）。--keep でアプリを終了せず残す（スクリーンショット用）。

例:
  python3 scripts/console-run.py                                             # 公開鍵行を拾う
  python3 scripts/console-run.py --env MOBILE_IDE_SPIKE_AUTORUN=1 --env MOBILE_IDE_SPIKE_HOST=127.0.0.1 \\
      --env MOBILE_IDE_SPIKE_USER=d0ne1s --until "SPIKE done"
  python3 scripts/console-run.py --env MOBILE_IDE_TERMINAL_AUTORUN=1 --until "TERMINAL connected" --keep
"""
import os
import select
import subprocess
import sys
import time

BUNDLE = "com.d0ne1s.mobileide"
MARKERS = ("SPIKE ", "TERMINAL ")


def main(argv):
    device = None
    env_pairs = []
    until = None
    timeout = 60
    keep = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--device":
            device = argv[i + 1]; i += 2
        elif a == "--env":
            env_pairs.append(argv[i + 1]); i += 2
        elif a == "--until":
            until = argv[i + 1]; i += 2
        elif a == "--timeout":
            timeout = int(argv[i + 1]); i += 2
        elif a == "--keep":
            keep = True; i += 1
        else:
            sys.exit(f"unknown arg: {a}")

    env = dict(os.environ)
    prefix = "DEVICECTL_CHILD_" if device else "SIMCTL_CHILD_"
    for pair in env_pairs:
        k, v = pair.split("=", 1)
        env[prefix + k] = v

    if device:
        cmd = ["xcrun", "devicectl", "device", "process", "launch", "--device", device,
               "--console", "--terminate-existing", BUNDLE]
    else:
        subprocess.run(["xcrun", "simctl", "terminate", "booted", BUNDLE], capture_output=True)
        cmd = ["xcrun", "simctl", "launch", "--console", "booted", BUNDLE]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, text=True)

    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if not r:
            continue
        line = p.stdout.readline()
        if not line:
            break
        if line.startswith(MARKERS):
            print(line, end="", flush=True)
            if until is None or line.startswith(until):
                break
    else:
        print(f"TIMEOUT after {timeout}s", flush=True)

    if not keep and not device:
        subprocess.run(["xcrun", "simctl", "terminate", "booted", BUNDLE], capture_output=True)
    p.kill()


if __name__ == "__main__":
    main(sys.argv[1:])
