#!/bin/bash
# sshd の ClientAliveInterval が効いているかを、無言で消えたクライアントが刈られるかで見る。
#
#   bash scripts/verify-clientalive.sh [--wait 90] [--expect gone|remain]
#
# 仕組み: scripts/ssh-proxy.py（127.0.0.1:2222 → 22）経由で素の ssh を張って tmux セッション
# `clientalive` に attach し、proxy を SIGUSR1 で凍結（ソケットは保ったまま中継停止）する。
# sshd から見ると keepalive の応答が返らない状態なので、その接続の sshd-session が終わり、tmux
# クライアントも消える。OpenSSH は未応答の数が CountMax を「超えた」ときに切るので、切れるのは
# 最後の受信から ClientAliveInterval × (CountMax + 1) = 15 × 4 = 60 秒（45 秒ではない）。
# 2 秒ごとに見て消えた時刻を出す。既定の ClientAliveInterval 0 なら --wait を過ぎても両方残る
# （--expect remain で陰性対照）。
#
# アプリを刺激に使わない理由: 再接続時の `tmux new-session -A -D` で古いクライアントが蹴られ、
# 設定に関係なく消える。sshd-session を kill -STOP しない理由: keepalive を送るのは sshd-session
# 自身なので、止めるとタイマーごと止まって設定に関係なく残る。
set -euo pipefail
WAIT=90
EXPECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wait) shift; WAIT="$1" ;;
    --expect) shift; EXPECT="$1" ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
export PATH="/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
SESSION=clientalive
LOG="$(mktemp /tmp/clientalive.XXXXXX)"
PROXY_PID=""
SSH_PID=""
cleanup() {
  [ -n "$SSH_PID" ] && kill "$SSH_PID" 2>/dev/null
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null
  tmux kill-session -t "$SESSION" 2>/dev/null
  rm -f "$LOG"
  return 0
}
trap cleanup EXIT

tmux kill-session -t "$SESSION" 2>/dev/null || true
python3 "${HERE}/ssh-proxy.py" >"$LOG" 2>&1 &
PROXY_PID=$!
sleep 1
grep -q 'PROXY listening' "$LOG" || { echo "FAIL proxy が起動しない"; cat "$LOG"; exit 1; }
tmux new-session -d -s "$SESSION" -c /tmp

( sleep $((WAIT + 60)) | TERM=xterm-256color script -q /dev/null \
    ssh -p 2222 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 localhost \
    -t "PATH=/opt/homebrew/bin:\$PATH tmux attach -t ${SESSION}" ) >/dev/null 2>&1 &
SSH_PID=$!
disown "$SSH_PID"   # 後片付けの kill で Terminated の通知を出さない

for _ in $(seq 1 30); do
  [ "$(tmux list-clients -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] && break
  sleep 0.5
done
CLIENT="$(tmux list-clients -t "$SESSION" -F '#{client_tty} #{client_pid} #{client_created}' 2>/dev/null | head -1)"
[ -n "$CLIENT" ] || { echo "FAIL proxy 経由の ssh が tmux に attach できない"; cat "$LOG"; exit 1; }
TTY="${CLIENT%% *}"
SSHD_PID="$(pgrep -f "sshd-session: ${USER}@${TTY#/dev/}" | head -1 || true)"
echo "client: ${CLIENT}"
echo "sshd-session: pid=${SSHD_PID:-?} ($(ps -o command= -p "${SSHD_PID:-0}" 2>/dev/null || echo '見つからない'))"
[ -n "$SSHD_PID" ] || { echo "FAIL この tty の sshd-session が見つからない"; exit 1; }

kill -USR1 "$PROXY_PID"
sleep 1
grep -q 'freeze on' "$LOG" || { echo "FAIL proxy が凍結しない"; cat "$LOG"; exit 1; }
echo "freeze on: 最大 ${WAIT} 秒待つ（2 秒ごとに見る）"
T0=$(date +%s)
elapsed=0
while :; do
  client_left="$(tmux list-clients -t "$SESSION" -F '#{client_tty} #{client_created}' 2>/dev/null | grep -c "^${TTY} " || true)"
  if ps -p "$SSHD_PID" >/dev/null 2>&1; then sshd_left=1; else sshd_left=0; fi
  elapsed=$(( $(date +%s) - T0 ))
  state="client=$([ "${client_left:-0}" -ge 1 ] && echo remain || echo gone) sshd=$([ "$sshd_left" = 1 ] && echo remain || echo gone)"
  if [ "$state" != "${last_state:-}" ]; then echo "  t=${elapsed}s ${state}"; last_state="$state"; fi
  { [ "${client_left:-0}" -eq 0 ] && [ "$sshd_left" = 0 ]; } && break
  [ "$elapsed" -ge "$WAIT" ] && break
  sleep 2
done
echo "after ${elapsed}s: tmux client $([ "${client_left:-0}" -ge 1 ] && echo remain || echo gone) / sshd-session $([ "$sshd_left" = 1 ] && echo remain || echo gone)"
kill -USR1 "$PROXY_PID" 2>/dev/null || true   # 凍結解除

if [ "${client_left:-0}" -ge 1 ] || [ "$sshd_left" = 1 ]; then observed=remain; else observed=gone; fi
[ "${client_left:-0}" -ge 1 ] && [ "$sshd_left" = 0 ] && observed=mixed
[ "${client_left:-0}" -eq 0 ] && [ "$sshd_left" = 1 ] && observed=mixed
if [ -n "$EXPECT" ]; then
  if [ "$observed" = "$EXPECT" ]; then echo "PASS expect=${EXPECT}"; else echo "FAIL expect=${EXPECT} observed=${observed}"; exit 1; fi
else
  echo "observed=${observed}"
fi
