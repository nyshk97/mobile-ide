"""SSH スパイク（#2）の自走ドライバ。アプリを --console 付きで起動し、stdout の SPIKE 行を集めて終了する。
使い方: python3 scripts/spike-run.py [--device ID] [--autorun HOST USER] [--timeout SEC] [--keep]
--device を付けると devicectl（実機）、無ければ simctl（シミュレータ）。
"""
import os, subprocess, sys, time, select
BUNDLE = "com.d0ne1s.mobileide"
args = sys.argv[1:]
env = dict(os.environ)
stop_marker = "SPIKE pubkey"
timeout = 60
device = args[args.index("--device")+1] if "--device" in args else None
prefix = "DEVICECTL_CHILD_" if device else "SIMCTL_CHILD_"
if "--autorun" in args:
    i = args.index("--autorun")
    env[prefix + "MOBILE_IDE_SPIKE_AUTORUN"] = "1"
    env[prefix + "MOBILE_IDE_SPIKE_HOST"] = args[i+1]
    env[prefix + "MOBILE_IDE_SPIKE_USER"] = args[i+2]
    stop_marker = "SPIKE done"
if "--timeout" in args:
    timeout = int(args[args.index("--timeout")+1])
if device:
    cmd = ["xcrun", "devicectl", "device", "process", "launch", "--device", device,
           "--console", "--terminate-existing", BUNDLE]
else:
    subprocess.run(["xcrun", "simctl", "terminate", "booted", BUNDLE], capture_output=True)
    cmd = ["xcrun", "simctl", "launch", "--console", "booted", BUNDLE]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, text=True)
deadline = time.time() + timeout
lines = []
while time.time() < deadline:
    r, _, _ = select.select([p.stdout], [], [], 0.5)
    if not r:
        continue
    line = p.stdout.readline()
    if not line:
        break
    if line.startswith("SPIKE "):
        lines.append(line.rstrip("\n"))
        print(line, end="", flush=True)
        if line.startswith(stop_marker):
            break
else:
    print(f"TIMEOUT after {timeout}s", flush=True)
if "--keep" not in args and not device:
    subprocess.run(["xcrun", "simctl", "terminate", "booted", BUNDLE], capture_output=True)
p.kill()
