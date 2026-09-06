"""チャット入力欄（composer）のシミュレータ自走検証。リポジトリルートで実行する。

前提: `mise run boot && mise run install` 済み、PolePole の一覧に `form` がある、`/tmp/mobile-ide-test.png`（scripts/make-test-images.sh）。
接続先は環境変数 MOBILE_IDE_HOST / MOBILE_IDE_USER（既定 127.0.0.1 / d0ne1s）。tmux セッションは `form` を使い、毎シナリオ作り直す。
Claude Code / Codex を実際に起こして 2 行を 1 入力として送るシナリオがあるので、両方がホストに入っていること。

検証項目:
  1. bracketed paste の包みを tmux がペインのモードに合わせて剥がす（`?2004l` の cat -v）/ 通す（`?2004h` の cat -v）
  2. Claude Code に 2 行が 1 回の送信として入る
  3. Codex に 2 行が 1 回の入力として入る
  4. スラッシュコマンドは composer モードでは入力欄へ、direct モードでは PTY へ
  5. 画像添付のパスは composer モードでは入力欄へ（PTY に出ない）
  6. inputMode の切替で目印行が出て、direct では入力欄が消えて端末の行数が増える
  7. モードの保存 → 上書き無しの通常起動で復元（direct のまま開く）
  8. 下書きの保存 → 画面を閉じて開き直すと復元
"""
import os, re, subprocess, sys, time
T = "/opt/homebrew/bin/tmux"
HOST = os.environ.get("MOBILE_IDE_HOST", "127.0.0.1")
USER = os.environ.get("MOBILE_IDE_USER", "d0ne1s")
CONN_ENV = ["--env", f"MOBILE_IDE_HOST={HOST}", "--env", f"MOBILE_IDE_USER={USER}", "--env", "MOBILE_IDE_OPEN_PROJECT=form"]
PNG = "/tmp/mobile-ide-test.png"
HARMLESS = "これはテスト送信です。何もせず「OK」とだけ返答して\\n2 行目"
# ESC[200~ + 本文（改行は \r）+ ESC[201~ + \r
HELLO_BYTES = len(b"\x1b[200~") + len("hello\rworld".encode()) + len(b"\x1b[201~") + 1

def tmux(*a): return subprocess.run([T, *a], capture_output=True, text=True).stdout.strip()
def pane(): return tmux("capture-pane", "-p", "-t", "form")
def fresh_session():
    tmux("kill-session", "-t", "form"); time.sleep(0.3)
def console(env, until, timeout=60):
    cmd = ["python3", "scripts/console-run.py", "--until", until, "--timeout", str(timeout), "--keep"] + CONN_ENV
    for k, v in env.items(): cmd += ["--env", f"{k}={v}"]
    return subprocess.run(cmd, capture_output=True, text=True).stdout
def wait(pred, sec=30):
    for _ in range(sec * 2):
        if pred(): return True
        time.sleep(0.5)
    return False
results = []
def check(name, ok, detail):
    results.append((name, ok, detail)); print(f"{'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)
def markers(out, prefix): return [l for l in out.splitlines() if l.startswith(prefix)]

# 0. 前提を揃える: 保存されている form のモードが direct なら composer に戻す（前回の実行が途中で止まった場合）
fresh_session()
out = console({}, "COMPOSE mode=")
if "COMPOSE mode=direct" in out:
    out = console({"MOBILE_IDE_PRESS_KEYS": "inputMode"}, "KEYS done")
    print("reset mode:", markers(out, "COMPOSE mode=")[-1], flush=True)

# 1. 包みの剥がし / 通し（cat -v）
fresh_session()
out = console({"MOBILE_IDE_TERMINAL_TYPE": 'printf "\\\\e[?2004l"; cat -v\\n', "MOBILE_IDE_COMPOSE": "hello\\nworld"}, "COMPOSE sent")
time.sleep(1); p = pane()
check("ペイン OFF: 包みが剥がれて 2 行", "hello\nworld" in p and "200~" not in p and f"COMPOSE sent bytes={HELLO_BYTES}" in out,
      [l for l in p.splitlines() if l.strip()][-2:])
tmux("send-keys", "-t", "form", "C-c"); fresh_session()
out = console({"MOBILE_IDE_TERMINAL_TYPE": 'printf "\\\\e[?2004h"; cat -v\\n', "MOBILE_IDE_COMPOSE": "hello\\nworld"}, "COMPOSE sent")
time.sleep(1); p = pane()
check("ペイン ON: 包みごと届き \\r が外", "^[[200~hello\nworld^[[201~" in p, [l for l in p.splitlines() if l.strip()][-2:])
tmux("send-keys", "-t", "form", "C-c"); fresh_session()

# 2. Claude Code に 2 行を 1 回で
out = console({"MOBILE_IDE_PRESS_KEYS": "claude", "MOBILE_IDE_COMPOSE": HARMLESS, "MOBILE_IDE_COMPOSE_AFTER": "10"}, "COMPOSE sent", 60)
ok = wait(lambda: "OK" in pane() and "テスト送信" in pane(), 60); time.sleep(2); p = pane()
lines = [l for l in p.splitlines() if l.strip()]
# 送った本文が 1 つの入力として見える（畳まれた [Pasted text +N lines] でも、2 行がそのまま出ていてもよい）。「2 行目」が別のプロンプトとして送られていない
prompts = [l for l in lines if l.lstrip().startswith(">") and "2 行目" in l and "テスト送信" not in l]
check("Claude: 2 行が 1 回の送信", ok and not prompts, lines[-8:])
tmux("send-keys", "-t", "form", "Escape"); time.sleep(0.5); tmux("send-keys", "-t", "form", "/exit", "Enter"); time.sleep(3)
fresh_session()

# 3. Codex に 2 行を 1 回で
out = console({"MOBILE_IDE_PRESS_KEYS": "codex", "MOBILE_IDE_COMPOSE": HARMLESS, "MOBILE_IDE_COMPOSE_AFTER": "14"}, "COMPOSE sent", 60)
ok = wait(lambda: "OK" in pane() and "テスト送信" in pane(), 60); time.sleep(2); p = pane()
lines = [l for l in p.splitlines() if l.strip()]
flags = subprocess.run(["ps", "-axo", "args"], capture_output=True, text=True).stdout
check("Codex: 2 行が 1 回の入力", ok and "danger-full-access" in flags, lines[-8:])
tmux("send-keys", "-t", "form", "C-c"); time.sleep(1); tmux("send-keys", "-t", "form", "C-c"); time.sleep(1)
fresh_session()

# 4. スラッシュコマンドの行き先
out = console({"MOBILE_IDE_PRESS_KEYS": "/dig"}, "KEYS done")
time.sleep(1); p = pane()
check("composer: /dig は入力欄へ", "COMPOSE inserted /dig " in out and "/dig" not in p, markers(out, "COMPOSE inserted"))
out = console({"MOBILE_IDE_INPUT_MODE": "direct", "MOBILE_IDE_PRESS_KEYS": "/dig"}, "KEYS done")
ok = wait(lambda: "/dig" in pane(), 5)
check("direct: /dig は PTY へ", ok and "COMPOSE inserted" not in out and "COMPOSE mode=direct" in out, [l for l in pane().splitlines() if "/dig" in l][:1])
tmux("send-keys", "-t", "form", "C-u")

# 5. 画像添付のパスは入力欄へ
out = console({"MOBILE_IDE_UPLOAD_FILE": PNG}, "UPLOAD typed", 90)
time.sleep(1); p = pane()
inserted = markers(out, "COMPOSE inserted @")
check("composer: @path は入力欄へ", bool(inserted) and "@/Users" not in p and "uploads" not in p, inserted[:1])

# 6. inputMode の切替（direct で入力欄が消えて行数が増える）
out = console({"MOBILE_IDE_PRESS_KEYS": "inputMode,inputMode"}, "KEYS done")
modes = [l.split("=")[1] for l in markers(out, "COMPOSE mode=")]
sizes = [int(re.search(r"(\d+)x(\d+)", l).group(2)) for l in markers(out, "TERMINAL size")]
check("inputMode 切替の目印行", modes == ["composer", "direct", "composer"], modes)
check("direct で端末の行数が増える", len(sizes) >= 2 and max(sizes) > sizes[0], sizes)

# 7. モードの保存 → 通常起動で復元（MOBILE_IDE_INPUT_MODE を付けない）
# pressKeys は開くたびに走るので、2 回目の open で direct → composer に戻り、保存値も composer に戻る（次のシナリオの前提）
out = console({"MOBILE_IDE_PRESS_KEYS": "inputMode", "MOBILE_IDE_CLOSE_AFTER": "3", "MOBILE_IDE_OPEN_TIMES": "2"}, "NEVER", 25)
modes = [l.split("=")[1] for l in markers(out, "COMPOSE mode=")]
check("direct を保存 → 2 回目は direct で開く（→ 再度押して composer に戻る）", modes == ["composer", "direct", "direct", "composer"], modes)

# 8. 下書きの保存 → 開き直しで復元
# 4 と 5 で入力欄に入れた `/dig ` と `@path ` が下書きとして残っている（変わるたびに保存する設計）。まず cat に流して空にする
def flush_draft():
    fresh_session()
    out = console({"MOBILE_IDE_TERMINAL_TYPE": "cat\\n", "MOBILE_IDE_COMPOSE": "."}, "COMPOSE sent")
    time.sleep(1)
    return out, pane()
out, p = flush_draft()
print("flushed:", markers(out, "COMPOSE draft"), flush=True)
# 2 回目の open の自走（DRAFT の挿入）まで終わるのを待つ（until を restored にすると挿入前に次の起動で殺してしまう）
out = console({"MOBILE_IDE_DRAFT": "途中", "MOBILE_IDE_CLOSE_AFTER": "3", "MOBILE_IDE_OPEN_TIMES": "2"}, "NEVER", 22)
check("下書きが復元される", markers(out, "COMPOSE draft") == ["COMPOSE draft set n=2", "COMPOSE draft restored n=2", "COMPOSE draft set n=4"],
      markers(out, "COMPOSE draft"))
# 後片付け: 2 回目の open でも DRAFT が足されるので復元される下書きは「途中途中」（n=4）。cat に流して空にする
out, p = flush_draft()
check("下書きの後片付け（途中途中. が cat に届く）", "途中途中." in p and "COMPOSE draft restored n=4" in out, [l for l in p.splitlines() if "途中" in l][:1])
tmux("send-keys", "-t", "form", "C-c"); time.sleep(0.5); tmux("kill-session", "-t", "form")
subprocess.run(["xcrun", "simctl", "terminate", "booted", "com.d0ne1s.mobileide"], capture_output=True)

passed = sum(1 for _, ok, _ in results if ok)
print(f"SUMMARY: {passed} / {len(results)} passed", flush=True)
sys.exit(0 if passed == len(results) else 1)
