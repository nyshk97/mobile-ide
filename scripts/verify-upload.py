"""画像添付（#8）のシミュレータ自走検証。リポジトリルートで実行する。

前提: `mise run boot && mise run install` 済み。sshd（22）と tmux はこの Mac のもの。
tmux セッションは `form`（`MOBILE_IDE_OPEN_PROJECT=form`。`mobile-ide` は実機と衝突する）。
DEBUG の `MOBILE_IDE_UPLOAD_FILE` でホスト側のファイルを画像添付と同じ経路（変換 → SFTP → `@path ` 流し込み）で送る。

検証項目:
  1. JPEG + PNG の 2 枚: 縮小と形式（2048x1536 JPEG / 945x2048 PNG）、`@a @b ` の順、進捗 1/2 → 2/2、端末に打ち込まれる
  2. 部分失敗: 壊れたファイルを混ぜると成功分だけ流し込み、`done n=1 failed=1` とアラート
  3. `~/.claude/uploads/` が無くても作られる（mkdir -p）。2 回目も通る
  4. アップロード専用の接続だけ失敗しても端末は切れない（中継の新規拒否）
  5. Claude Code が流し込まれたパスの画像を読んで答える（tmux 上の対話経路）

スクリーンショット: /tmp/mobile-ide-upload-partial.png（部分失敗のアラート）, /tmp/mobile-ide-upload-failed.png（失敗のアラート）
tmux サーバーは GUI セッションから起動されている必要がある（sshd 起動のサーバーだと Claude Code が Not logged in になる。VERIFY.md）。
"""
import os
import re
import signal
import subprocess
import sys
import threading
import time

T = "/opt/homebrew/bin/tmux"
USER = os.environ.get("MOBILE_IDE_USER", "d0ne1s")
SESSION = os.environ.get("MOBILE_IDE_VERIFY_PROJECT", "form")
HOME = os.path.expanduser("~")
UPLOADS = f"{HOME}/.claude/uploads"
LOG_DIR = "/tmp"
JPG, PNG, BROKEN = "/tmp/mobile-ide-test.jpg", "/tmp/mobile-ide-test.png", "/tmp/mobile-ide-broken.jpg"

results = []


def check(name, ok, detail):
    results.append((name, ok, detail))
    print(f"{'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def tmux(*a):
    return subprocess.run([T, *a], capture_output=True, text=True).stdout.strip()


def pane():
    return tmux("capture-pane", "-p", "-t", SESSION)


def shot(name):
    subprocess.run(["xcrun", "simctl", "io", "booted", "screenshot", f"{LOG_DIR}/mobile-ide-{name}"], capture_output=True)


def sips(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    w = re.search(r"pixelWidth: (\d+)", out)
    h = re.search(r"pixelHeight: (\d+)", out)
    return (int(w.group(1)), int(h.group(1))) if w and h else None


def filetype(path):
    return subprocess.run(["file", "-b", path], capture_output=True, text=True).stdout.split(",")[0].strip()


class App:
    """console-run.py を裏で走らせ、目印行を集める（#7 の verify-reconnect.py と同じ）"""

    def __init__(self, name, env, timeout=120, host="127.0.0.1", port=22):
        self.path = f"{LOG_DIR}/mobile-ide-{name}.log"
        cmd = [sys.executable, "scripts/console-run.py", "--until", "NEVERMATCH", "--timeout", str(timeout), "--keep",
               "--env", f"MOBILE_IDE_HOST={host}", "--env", f"MOBILE_IDE_PORT={port}", "--env", f"MOBILE_IDE_USER={USER}",
               "--env", f"MOBILE_IDE_OPEN_PROJECT={SESSION}",
               # 既定のチャット入力欄モードでは `@path ` は入力欄に入る（scripts/verify-composer.py が見る）。ここは端末への流し込みを見る
               "--env", "MOBILE_IDE_INPUT_MODE=direct"]
        for k, v in env.items():
            cmd += ["--env", f"{k}={v}"]
        self.out = open(self.path, "wb")
        self.p = subprocess.Popen(cmd, stdout=self.out, stderr=subprocess.STDOUT)
        self.lines = []
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
        with self.lock:
            new = data.splitlines()[self.seen:]
            self.lines.extend(new)
            self.seen += len(new)

    def wait(self, pattern, count=1, timeout=90):
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.poll()
            if sum(1 for l in self.lines if pattern in l) >= count:
                return True
            time.sleep(0.2)
        return False

    def has(self, pattern):
        self.poll()
        return any(pattern in l for l in self.lines)

    def grep(self, pattern):
        self.poll()
        return [l for l in self.lines if pattern in l]

    def upload_lines(self):
        return self.grep("UPLOAD ")

    def stop(self):
        self.alive = False
        self.p.kill()


def put_paths(app):
    return [l.split()[2] for l in app.grep("UPLOAD put ")]


# ---- 準備 ---------------------------------------------------------------------------------------
subprocess.run(["bash", "scripts/make-test-images.sh", "/tmp"], capture_output=True, check=True)
with open(BROKEN, "w") as f:
    f.write("this is not an image\n")
tmux("kill-session", "-t", SESSION)

# ---- 1. JPEG + PNG の 2 枚 ------------------------------------------------------------------------
app = App("u1", {"MOBILE_IDE_UPLOAD_FILE": f"{JPG},{PNG}"})
app.wait("TERMINAL connected", timeout=60)
ok = app.wait("UPLOAD typed", timeout=90)
time.sleep(2)
paths = put_paths(app)
typed = app.grep("UPLOAD typed ")
sizes = [sips(p) for p in paths]
types = [filetype(p) for p in paths]
check("1a 2 枚とも変換・転送され、目印行が start → progress 1/2, 2/2 → done n=2 failed=0",
      ok and app.has("UPLOAD start n=2") and app.has("UPLOAD progress 1/2") and app.has("UPLOAD progress 2/2")
      and app.has("UPLOAD done n=2 failed=0") and len(paths) == 2,
      app.upload_lines())
check("1b サイズと形式: JPEG は 2048x1536、PNG は 945x2048 で PNG のまま",
      len(paths) == 2 and paths[0].endswith(".jpg") and paths[1].endswith(".png")
      and sizes == [(2048, 1536), (945, 2048)] and types[0].startswith("JPEG") and types[1].startswith("PNG"),
      f"paths={paths} sizes={sizes} types={types}")
expected_typed = "".join(f"@{p} " for p in paths)
check("1c 端末に `@jpg @png ` の順で打ち込まれた（tmux の pane に見える）",
      typed and typed[0].endswith(expected_typed) and paths and paths[0] in pane(),
      f"typed={typed[:1]} pane={[l for l in pane().splitlines() if '@' in l][:2]}")
tmux("send-keys", "-t", SESSION, "C-u")  # 打ち込んだ文字列を消す

# ---- 2. 部分失敗 -----------------------------------------------------------------------------------
app.stop()
app = App("u2", {"MOBILE_IDE_UPLOAD_FILE": f"{JPG},{BROKEN}"})
app.wait("TERMINAL connected", timeout=60)
ok = app.wait("UPLOAD typed", timeout=90)
time.sleep(2)
shot("upload-partial.png")
paths2 = put_paths(app)
check("2 壊れた 1 枚は数えられ、成功した 1 枚だけ流し込まれる（done n=1 failed=1）",
      ok and app.has("UPLOAD done n=1 failed=1") and len(paths2) == 1 and app.grep("UPLOAD typed ")[0].count("@") == 1,
      app.upload_lines())
tmux("send-keys", "-t", SESSION, "C-u")

# ---- 3. mkdir -p（ディレクトリが無い状態から）-------------------------------------------------------
app.stop()
backup = f"{UPLOADS}.verify-backup"
if os.path.isdir(UPLOADS):
    os.rename(UPLOADS, backup)
try:
    app = App("u3", {"MOBILE_IDE_UPLOAD_FILE": JPG})
    app.wait("TERMINAL connected", timeout=60)
    ok = app.wait("UPLOAD done", timeout=90)
    created = os.path.isdir(UPLOADS) and len(put_paths(app)) == 1 and os.path.isfile(put_paths(app)[0])
    app.stop()
    app = App("u3b", {"MOBILE_IDE_UPLOAD_FILE": JPG})
    app.wait("TERMINAL connected", timeout=60)
    ok2 = app.wait("UPLOAD done", timeout=90)
    check("3 uploads ディレクトリが無くても作られ（mkdir -p）、2 回目も通る", ok and created and ok2, f"created={created} second={ok2}")
finally:
    if os.path.isdir(backup):
        # 検証中にできたファイルは退避したディレクトリに移してから戻す
        if os.path.isdir(UPLOADS):
            for name in os.listdir(UPLOADS):
                os.rename(f"{UPLOADS}/{name}", f"{backup}/{name}")
            os.rmdir(UPLOADS)
        os.rename(backup, UPLOADS)
tmux("send-keys", "-t", SESSION, "C-u")

# ---- 4. アップロード専用の接続だけ失敗（端末は生きたまま）------------------------------------------
app.stop()
proxy_log = open(f"{LOG_DIR}/mobile-ide-proxy.log", "ab")
proxy = subprocess.Popen([sys.executable, "scripts/ssh-proxy.py", "--listen", "2222"], stdout=proxy_log, stderr=subprocess.STDOUT)
time.sleep(0.8)
try:
    app = App("u4", {"MOBILE_IDE_UPLOAD_FILE": JPG, "MOBILE_IDE_UPLOAD_AFTER": "6"}, port=2222)
    app.wait("TERMINAL connected", timeout=60)
    time.sleep(2)
    proxy.send_signal(signal.SIGUSR2)  # 新規接続だけ拒否
    ok = app.wait("UPLOAD failed", timeout=60)
    time.sleep(2)
    shot("upload-failed.png")
    check("4 アップロード専用の接続だけ失敗し、端末は切れない（TERMINAL lost が出ない）",
          ok and not app.has("TERMINAL lost") and not app.has("UPLOAD put"),
          app.upload_lines() + app.grep("TERMINAL lost"))
    proxy.send_signal(signal.SIGUSR2)
finally:
    proxy.terminate()

# ---- 5. Claude Code が画像を読む（tmux 上の対話経路）--------------------------------------------------
app.stop()
tmux("send-keys", "-t", SESSION, "C-u")
tmux("send-keys", "-t", SESSION, "claude", "Enter")
started = False
for _ in range(60):
    time.sleep(1)
    if "shift+tab to cycle" in pane():
        started = True
        break
not_logged_in = "Not logged in" in pane()
app = App("u5", {"MOBILE_IDE_UPLOAD_FILE": JPG})
app.wait("TERMINAL connected", timeout=60)
ok = app.wait("UPLOAD typed", timeout=90)
time.sleep(1)
tmux("send-keys", "-t", SESSION, "-l", "この画像に何が写っているか一言で")
tmux("send-keys", "-t", SESSION, "Enter")
answered = False
for _ in range(90):
    time.sleep(1)
    text = pane()
    if re.search(r"黄|yellow|JPEG|青い(円|丸)|blue", text) and "⏺" in text:
        answered = True
        break
answer = [l for l in pane().splitlines() if l.strip().startswith("⏺")][-1:]
check("5 Claude Code が流し込まれたパスの画像を読んで内容を答える", started and not not_logged_in and ok and answered,
      f"started={started} not_logged_in={not_logged_in} answer={answer}")
tmux("send-keys", "-t", SESSION, "C-c")
time.sleep(0.5)
tmux("send-keys", "-t", SESSION, "C-c")

app.stop()
print("\nSUMMARY:", sum(1 for r in results if r[1]), "/", len(results), "passed")
sys.exit(0 if all(r[1] for r in results) else 1)
