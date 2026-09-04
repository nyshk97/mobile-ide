"""再接続（#7）のシミュレータ自走検証。リポジトリルートで実行する。

前提: `mise run boot && mise run install` 済み。sshd（22）と tmux はこの Mac のもの。
アプリは scripts/ssh-proxy.py（127.0.0.1:2222 → 22）経由で接続させ、中継を切る・凍結する・止めることで
回線断・無音の断・接続拒否を起こす。sshd と authorized_keys には触らない。
接続先ユーザーは環境変数 MOBILE_IDE_USER（既定 d0ne1s）。
tmux セッションは MOBILE_IDE_VERIFY_PROJECT（既定 `form`。PolePole の一覧にある tmux セッション名）を使う。
`mobile-ide` を使わないのは、実機 iPhone が同じセッションに attach していると `-D` で互いに蹴り合い、クライアント数の判定が狂うため。
このセッションは途中で kill する（シナリオ 5）ので、作業中のものを指定しない。

検証項目:
  1. 回線断（中継が TCP を切る）→ 自動で同じ tmux セッションに再接続する
  2. 接続拒否が続く間はバックオフ（1, 2, 4, 8, 15 秒）で試し続け、復旧した次の試行で繋がる。多重化しない
  3. 無音の断（中継を凍結）→ 生存判定が 3 秒で死を検出し即時再接続。古いクライアントは -D で蹴られる
  4. 生きていれば生存判定は何もしない（再接続が走らない）
  5. シェルの exit（tmux セッションを kill）は自動再接続しない

スクリーンショット: /tmp/mobile-ide-reconnecting.png（バナー）, /tmp/mobile-ide-exited.png（全面オーバーレイ）
"""
import os
import signal
import subprocess
import sys
import threading
import time

T = "/opt/homebrew/bin/tmux"
USER = os.environ.get("MOBILE_IDE_USER", "d0ne1s")
PORT = 2222
SESSION = os.environ.get("MOBILE_IDE_VERIFY_PROJECT", "form")
LOG_DIR = "/tmp"
CONN_ENV = ["--env", "MOBILE_IDE_HOST=127.0.0.1", "--env", f"MOBILE_IDE_PORT={PORT}", "--env", f"MOBILE_IDE_USER={USER}",
            "--env", f"MOBILE_IDE_OPEN_PROJECT={SESSION}"]

results = []


def check(name, ok, detail):
    results.append((name, ok, detail))
    print(f"{'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def tmux(*a):
    return subprocess.run([T, *a], capture_output=True, text=True).stdout.strip()


def clients():
    """(client_created, WxH) の一覧"""
    out = tmux("list-clients", "-t", SESSION, "-F", "#{client_created} #{client_width}x#{client_height}")
    return [tuple(l.split()) for l in out.splitlines() if l]


def shot(name):
    subprocess.run(["xcrun", "simctl", "io", "booted", "screenshot", f"{LOG_DIR}/mobile-ide-{name}"], capture_output=True)


class Proxy:
    def __init__(self):
        self.p = None

    def start(self):
        self.log = open(f"{LOG_DIR}/mobile-ide-proxy.log", "ab")
        self.p = subprocess.Popen([sys.executable, "scripts/ssh-proxy.py", "--listen", str(PORT)], stdout=self.log, stderr=subprocess.STDOUT)
        time.sleep(0.8)

    def signal(self, sig):
        self.p.send_signal(sig)

    def stop(self):
        if self.p and self.p.poll() is None:
            self.p.terminate()
            self.p.wait(timeout=5)


class App:
    """console-run.py を裏で走らせ、目印行を時刻付きで集める。
    収集はスレッドで 0.1 秒ごとに回す（メインが sleep している間も時刻がずれないように）"""

    def __init__(self, name, extra_env=(), timeout=120):
        self.path = f"{LOG_DIR}/mobile-ide-{name}.log"
        cmd = [sys.executable, "scripts/console-run.py", "--until", "NEVERMATCH", "--timeout", str(timeout), "--keep"] + CONN_ENV
        for e in extra_env:
            cmd += ["--env", e]
        self.out = open(self.path, "wb")
        self.p = subprocess.Popen(cmd, stdout=self.out, stderr=subprocess.STDOUT)
        self.lines = []  # (time, line)
        self.seen = 0
        self.lock = threading.Lock()
        self.alive = True
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while self.alive:
            self.poll()
            time.sleep(0.1)

    def poll(self):
        with open(self.path, "rb") as f:
            data = f.read().decode("utf-8", "replace")
        now = time.time()
        with self.lock:
            new = data.splitlines()[self.seen:]
            for l in new:
                self.lines.append((now, l))
            self.seen += len(new)

    def wait(self, pattern, count=1, timeout=60):
        """pattern を含む行が count 個そろうまで待つ。そろった時刻を返す（無ければ None）"""
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.poll()
            if sum(1 for _, l in self.lines if pattern in l) >= count:
                return time.time()
            time.sleep(0.2)
        self.poll()
        return None

    def has(self, pattern):
        self.poll()
        return any(pattern in l for _, l in self.lines)

    def first_time(self, pattern):
        self.poll()
        for t, l in self.lines:
            if pattern in l:
                return t
        return None

    def terminal_lines(self):
        self.poll()
        return [l for _, l in self.lines if l.startswith("TERMINAL")]

    def stop(self):
        self.alive = False
        self.p.kill()


proxy = Proxy()
proxy.start()
tmux("kill-session", "-t", SESSION)  # 無い状態から始める（OPEN_PROJECT で開くと作られる）

# ---- 1. 回線断 → 自動再接続 -----------------------------------------------------------------
app = App("s1")
ok = app.wait("TERMINAL connected", timeout=60)
time.sleep(4)  # .zshrc → tmux attach が終わるのを待つ
created0 = tmux("display", "-p", "-t", SESSION, "#{session_created}")
before = clients()
drop_at = time.time()
proxy.signal(signal.SIGHUP)
ok = app.wait("TERMINAL connected", count=2, timeout=30)
time.sleep(2)
after = clients()
lines = app.terminal_lines()
check("1a 回線断を lost として検出し attempt=1 delay=1 で張り直す",
      ok and any("TERMINAL lost" in l for l in lines) and any("reconnecting attempt=1 delay=1" in l for l in lines)
      and not any("TERMINAL disconnected" in l for l in lines),
      lines[-4:])
check("1b 同じ tmux セッションに戻り、クライアントは断の後に作られた 1 件だけ",
      created0 != "" and created0 == tmux("display", "-p", "-t", SESSION, "#{session_created}")
      and len(after) == 1 and int(after[0][0]) >= int(drop_at) and before and before[0][1] == after[0][1],
      f"session_created={created0} before={before} after={after} drop_at={int(drop_at)}")

# ---- 2. バックオフ（中継を止めたまま）----------------------------------------------------------
proxy.stop()
t_kill = time.time()
app.wait("reconnecting attempt=1", count=2, timeout=15)  # シナリオ 1 の分があるので 2 個目
time.sleep(6)
shot("reconnecting.png")
ok = app.wait("reconnecting attempt=5", timeout=40)
proxy.start()
t_restart = time.time()
ok2 = app.wait("TERMINAL connected", count=3, timeout=40)
time.sleep(2)
# 2 回目以降の "reconnecting attempt=N" の時刻差（試行 N の失敗は即時なので、差 ≈ 遅延 N）
times = {}
app.poll()
skip1 = True
for t, l in app.lines:
    if "TERMINAL reconnecting attempt=" in l:
        n = int(l.split("attempt=")[1].split()[0])
        if n == 1 and skip1:
            skip1 = False
            continue
        times.setdefault(n, t)
deltas = [round(times[n + 1] - times[n], 1) for n in range(1, 5) if n in times and n + 1 in times]
expected = [1, 2, 4, 8]
check("2a 接続拒否の間は 1, 2, 4, 8 秒のバックオフで試す",
      ok is not None and len(deltas) == 4 and all(e <= d <= e + 3 for d, e in zip(deltas, expected)),
      f"deltas={deltas} expected≈{expected}")
check("2b 中継を戻すと次の試行（15 秒待ち）で繋がる。クライアントは 1 件",
      ok2 is not None and 0 <= ok2 - t_restart <= 20 and len(clients()) == 1,
      f"restart→connected={round(ok2 - t_restart, 1) if ok2 else None}s clients={clients()}")

# ---- 3. 無音の断（凍結）→ 生存判定 → 即時再接続 → -D で古いクライアントが消える -------------------
app.stop()
app = App("s3", extra_env=["MOBILE_IDE_PROBE_AFTER=6"])
app.wait("TERMINAL connected", timeout=60)
time.sleep(3)
frozen_clients = clients()
proxy.signal(signal.SIGUSR1)  # 凍結。古い接続のソケットは保たれ、tmux クライアントも残る
t_start = app.wait("TERMINAL probe start", timeout=20)
t_dead = app.wait("TERMINAL probe dead", timeout=10)
during = clients()  # 再接続の直前後。古いクライアントがまだ居るはず
ok = app.wait("TERMINAL connected", count=2, timeout=30)
time.sleep(3)
after = clients()
proxy.signal(signal.SIGUSR1)  # 解除
check("3a 凍結した接続を生存判定が 3 秒で死と判定し、遅延なしで張り直す",
      t_start and t_dead and 2.5 <= t_dead - t_start <= 5 and app.has("reconnecting attempt=1 delay=0") and ok,
      f"probe start→dead={round(t_dead - t_start, 1) if t_start and t_dead else None}s lines={app.terminal_lines()[-4:]}")
check("3b 古いクライアントが残っていたが、-D で蹴られて新しい 1 件だけになる",
      len(frozen_clients) == 1 and len(during) >= 1 and len(after) == 1 and int(after[0][0]) > int(frozen_clients[0][0]),
      f"frozen={frozen_clients} during={during} after={after}")

# ---- 4. 生きていれば何もしない ------------------------------------------------------------------
app.stop()
app = App("s4", extra_env=["MOBILE_IDE_PROBE_AFTER=6"])
app.wait("TERMINAL connected", timeout=60)
time.sleep(4)  # tmux クライアントが付くまで待ってから基準を取る
c0 = clients()
ok = app.wait("TERMINAL probe ok", timeout=20)
time.sleep(3)
check("4 生きている接続の生存判定は probe ok だけで再接続しない",
      ok and len(c0) == 1 and not app.has("reconnecting") and not app.has("TERMINAL lost") and clients() == c0,
      f"lines={app.terminal_lines()[-3:]} clients={clients()}")

# ---- 5. シェルの exit は自動再接続しない ----------------------------------------------------------
app.stop()
app = App("s5")
app.wait("TERMINAL connected", timeout=60)
time.sleep(4)
tmux("kill-session", "-t", SESSION)  # tmux クライアントが終わり、ログインシェルも exit する
ok = app.wait("TERMINAL disconnected", timeout=20)
time.sleep(4)
shot("exited.png")
check("5 セッション終了は shellExited で止まり、再接続が走らない",
      ok and app.has("TERMINAL disconnected shell exited") and not app.has("reconnecting") and not app.has("TERMINAL lost"),
      f"lines={app.terminal_lines()[-3:]}")

app.stop()
proxy.stop()
print("\nSUMMARY:", sum(1 for r in results if r[1]), "/", len(results), "passed")
sys.exit(0 if all(r[1] for r in results) else 1)
