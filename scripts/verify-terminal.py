"""端末（#3）のシミュレータ自走検証。リポジトリルートで実行する。

前提: `mise run boot && mise run install` 済み、Air 側で tmux セッション `mobile-ide` にアプリが attach 中
（`python3 scripts/console-run.py --env MOBILE_IDE_TERMINAL_AUTORUN=1 --until "TERMINAL connected" --keep`）。
tmux サーバーはこの Mac（= 開発中のホスト）上の同じユーザーのものを直接見る。
スクリーンショットは /tmp/mobile-ide-term-*.png に出る。

検証項目: Claude Code の起動描画 / detach でアプリが disconnected になる / detach 後もセッションが残る /
アプリからの入力が tmux に届く / -A で同じセッションに再 attach する / tmux クライアントサイズがアプリと一致する
"""
import subprocess, time, sys, os
S = "/tmp"
T = "/opt/homebrew/bin/tmux"
def tmux(*a): return subprocess.run([T, *a], capture_output=True, text=True).stdout.strip()
def shot(name):
    subprocess.run(["xcrun", "simctl", "io", "booted", "screenshot", f"{S}/mobile-ide-{name}"], capture_output=True)
def console(env, until, timeout=60):
    cmd = ["python3", "scripts/console-run.py", "--until", until, "--timeout", str(timeout), "--keep"]
    for k, v in env.items(): cmd += ["--env", f"{k}={v}"]
    return subprocess.run(cmd, capture_output=True, text=True).stdout
def wait(pred, sec=30):
    for _ in range(sec * 2):
        if pred(): return True
        time.sleep(0.5)
    return False
results = []
def check(name, ok, detail): results.append((name, ok, detail)); print(f"{'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)

created0 = tmux("display", "-p", "-t", "mobile-ide", "#{session_created}")

# 1. Claude Code の描画（tmux 内で起動 → スクショ → 終了）
tmux("send-keys", "-t", "mobile-ide", "claude", "Enter")
ok = wait(lambda: "Claude" in tmux("capture-pane", "-p", "-t", "mobile-ide") or "claude" in tmux("capture-pane", "-p", "-t", "mobile-ide").lower(), 20)
time.sleep(5); shot("term3-claude.png")
pane = tmux("capture-pane", "-p", "-t", "mobile-ide")
check("claude が tmux 内で起動", ok and len(pane.strip()) > 0, pane.strip().splitlines()[:2])
tmux("send-keys", "-t", "mobile-ide", "C-c"); time.sleep(0.5); tmux("send-keys", "-t", "mobile-ide", "C-c"); time.sleep(2)
wait(lambda: "mobile-ide on" in tmux("capture-pane", "-p", "-t", "mobile-ide").splitlines()[-2] if len(tmux("capture-pane", "-p", "-t", "mobile-ide").splitlines()) > 1 else False, 10)

# 2. 切断: 別プロセスで console を張り直し、tmux 側から detach → アプリが disconnected を出すか
launched_at = int(time.time())
p = subprocess.Popen(["python3", "scripts/console-run.py", "--env", "MOBILE_IDE_TERMINAL_AUTORUN=1",
                      "--until", "TERMINAL disconnected", "--timeout", "60", "--keep"],
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
# 起動後に作られたクライアント（古い実体の残骸でない）が付くまで待つ
def fresh_client():
    return any(l and int(l) >= launched_at for l in tmux("list-clients", "-t", "mobile-ide", "-F", "#{client_created}").splitlines())
wait(fresh_client, 60); time.sleep(2)
tmux("detach-client", "-s", "mobile-ide")
out = p.communicate(timeout=60)[0]
check("detach で disconnected", "TERMINAL disconnected shell exited" in out, [l for l in out.splitlines() if l.startswith("TERMINAL")])
time.sleep(1); shot("term4-disconnected.png")
check("detach 後もセッションが残る", tmux("has-session", "-t", "mobile-ide") == "" and tmux("list-sessions") != "", tmux("list-sessions"))

# 3. 再 attach（-A）+ 入力経路（アプリが自分で文字列を送る）
stamp = f"INPUT_OK_{int(time.time())}"
out = console({"MOBILE_IDE_TERMINAL_AUTORUN": "1", "MOBILE_IDE_TERMINAL_TYPE": f"echo {stamp}\\n"}, "TERMINAL connected")
ok = wait(lambda: stamp in tmux("capture-pane", "-p", "-t", "mobile-ide") and tmux("capture-pane", "-p", "-t", "mobile-ide").count(stamp) >= 2, 30)
check("入力経路（app → PTY → tmux）", ok, [l for l in tmux("capture-pane", "-p", "-t", "mobile-ide").splitlines() if stamp in l])
created1 = tmux("display", "-p", "-t", "mobile-ide", "#{session_created}")
check("-A で同じセッションに再 attach", created0 == created1 and created0 != "", f"created before={created0} after={created1}")
size_lines = [l for l in out.splitlines() if l.startswith("TERMINAL size")]
client = tmux("list-clients", "-t", "mobile-ide", "-F", "#{client_width}x#{client_height}")
check("クライアントサイズがアプリの最新サイズと一致", size_lines and size_lines[-1].split()[-1] == client, f"app={size_lines} tmux client={client}")
time.sleep(1); shot("term5-reattached.png")
print("\nSUMMARY:", sum(1 for r in results if r[1]), "/", len(results), "passed")
sys.exit(0 if all(r[1] for r in results) else 1)
