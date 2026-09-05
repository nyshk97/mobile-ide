#!/bin/bash
# mobile-ide のホスト（Mac）を準備する。冪等。2 回目は result=changed が 0 件になる。
#
#   bash scripts/host-setup.sh                         # 全部（Mac mini 用）
#   bash scripts/host-setup.sh --skip-power --skip-autologin   # ノート（Air）に当てるとき
#   bash scripts/host-setup.sh --dry-run               # 書かずに判定だけ
#   --brewfile <path>                                  # Brewfile の場所（既定: ~/Library/CloudStorage/Dropbox/Brewfile）
#
# 守備範囲は「Dropbox・Homebrew・mise・dotfiles の同期が済んだ Mac の続き」。土台が無ければ
# ステップ 0 で列挙して止まる（自前ではインストールしない）。sudo が要るので自分の Terminal で流す。
# Claude Code のセッションからは --dry-run だけ（sudo が無い項目は unknown になる）。
#
# 各ステップは「現状を読む → 目的と違うときだけ書く → step=<名前> result=<語> を 1 行出す」。
#   changed   = 書いた
#   unchanged = 既に目的の状態
#   skipped   = --skip-* で飛ばした
#   unknown   = 権限が無くて読めない（sudo 無しの --dry-run で出る）
#   failed    = 書いたが確認で目的の状態にならなかった（末尾の未完了リストに積む）
#
# なぜ sshd に ClientAliveInterval を入れるか: 切れた接続の sshd-session と tmux クライアントを
# 45 秒程度（15 秒 × 3）で掃除させるため。既定の 0 だと数時間残る。アプリ側は attach 時に -D で
# 古いクライアントを蹴るので無くても動くが、常時稼働のホストでは入れておく。
# なぜ 00- で置くか: sshd は先に読まれた値が勝つ。100-macos.conf 等に負けないように先頭に置く。
set -euo pipefail

DRY_RUN=0
SKIP_POWER=0
SKIP_AUTOLOGIN=0
BREWFILE="${HOME}/Library/CloudStorage/Dropbox/Brewfile"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-power) SKIP_POWER=1 ;;
    --skip-autologin) SKIP_AUTOLOGIN=1 ;;
    --brewfile) shift; BREWFILE="$1" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

SSHD_CONF=/etc/ssh/sshd_config.d/00-mobile-ide.conf
SSHD_WANT=$'PasswordAuthentication no\nKbdInteractiveAuthentication no\nClientAliveInterval 15\nClientAliveCountMax 3'
PENDING=()   # 人が続きをやる項目
CHANGED=0

report() { # step result [detail]
  local line="step=$1 result=$2"
  [ $# -ge 3 ] && line="$line $3"
  echo "$line"
  [ "$2" = "changed" ] && CHANGED=$((CHANGED + 1))
  return 0
}
pending() { PENDING+=("$1"); }

# root で読む。dry-run では sudo -n（パスワードを聞かない）で試し、無理なら 1 を返す。
root_read() {
  if [ "$DRY_RUN" = 1 ]; then sudo -n "$@" 2>/dev/null; else sudo "$@"; fi
}

# ---- 0. 前提チェック ------------------------------------------------------
missing=()
command -v brew >/dev/null 2>&1 || missing+=("Homebrew（brew）が無い")
command -v mise >/dev/null 2>&1 || missing+=("mise が無い")
NODE_BIN=""
if command -v mise >/dev/null 2>&1; then
  NODE_BIN="$(mise which node 2>/dev/null || true)"
  [ -n "$NODE_BIN" ] || missing+=("mise の node が無い（mise install node）")
fi
[ -r "$BREWFILE" ] || missing+=("Brewfile が読めない: ${BREWFILE}（Dropbox のサインインと同期）")
cat "${HOME}/.zshrc" >/dev/null 2>&1 || missing+=("~/.zshrc が読めない（setup-dotfiles.sh で symlink を張る。CloudStorage は TCC で止まることがある）")
if [ ${#missing[@]} -gt 0 ]; then
  report precheck failed
  echo "先に人がやること:"
  for m in "${missing[@]}"; do echo "  - ${m}"; done
  exit 2
fi
report precheck ok

# ---- 1. sshd ----------------------------------------------------------------
sshd_effective_ok() { # sudo sshd -T を読んで 4 つの実効値を突き合わせる。読めなければ 2
  local out
  out="$(root_read /usr/sbin/sshd -T 2>/dev/null)" || return 2
  local ok=1 k v
  for kv in "clientaliveinterval 15" "clientalivecountmax 3" "passwordauthentication no" "kbdinteractiveauthentication no"; do
    k="${kv% *}"; v="${kv#* }"
    echo "$out" | grep -q -i -E "^${k} ${v}\$" || { ok=0; echo "  sshd -T: ${k} が ${v} でない（$(echo "$out" | grep -i "^${k} " || echo '出力なし')）"; }
  done
  [ "$ok" = 1 ]
}
current="$(cat "$SSHD_CONF" 2>/dev/null || true)"
if [ "$current" = "$SSHD_WANT" ]; then
  if sshd_effective_ok; then report sshd unchanged
  elif [ $? -eq 2 ]; then report sshd unknown "conf は一致。実効値は sudo が無く未確認"
  else report sshd failed "conf は一致するが実効値が違う"; pending "sshd の実効値が違う。sudo sshd -T と /etc/ssh/sshd_config.d/ の他のファイルを確認"
  fi
elif [ "$DRY_RUN" = 1 ]; then
  report sshd changed "(dry-run) ${SSHD_CONF} を 4 行で書く"
else
  if ! sudo /usr/sbin/sshd -t; then
    report sshd failed "書く前から sshd -t が通らない（自分の変更ではない）"
    pending "sshd の設定が元から壊れている。sudo sshd -t の出力を見て直してから再実行"
  else
    backup="$(mktemp -d /tmp/host-setup.XXXXXX)"
    had_old=0
    if [ -e "$SSHD_CONF" ]; then sudo cp "$SSHD_CONF" "${backup}/00-mobile-ide.conf"; had_old=1; fi
    printf '%s\n' "$SSHD_WANT" | sudo tee "$SSHD_CONF" >/dev/null
    if ! sudo /usr/sbin/sshd -t; then
      if [ "$had_old" = 1 ]; then sudo cp "${backup}/00-mobile-ide.conf" "$SSHD_CONF"; else sudo rm -f "$SSHD_CONF"; fi
      report sshd failed "sshd -t が通らないので退避から戻した（退避: ${backup}）"
      echo "sshd の設定を書いたら構文エラーになった。締め出されないよう戻した。" >&2
      exit 1
    fi
    if sshd_effective_ok; then report sshd changed "退避: ${backup}"
    else report sshd failed "書いたが実効値が違う（退避: ${backup}）"; pending "sshd の実効値が違う。sudo sshd -T と /etc/ssh/sshd_config.d/ の他のファイルを確認"
    fi
  fi
fi

# ---- 2. リモートログイン -----------------------------------------------------
rl="$(root_read systemsetup -getremotelogin 2>/dev/null || true)"
case "$rl" in
  *": On"*) report remotelogin unchanged ;;
  *": Off"*)
    if [ "$DRY_RUN" = 1 ]; then report remotelogin changed "(dry-run) systemsetup -setremotelogin on"
    elif sudo systemsetup -setremotelogin on >/dev/null 2>&1; then report remotelogin changed
    else
      report remotelogin failed "systemsetup -setremotelogin on が失敗"
      pending "リモートログインを ON にする: System Settings → 一般 → 共有 → リモートログイン（または実行に使うターミナルにフルディスクアクセスを付けて再実行）"
    fi ;;
  *) report remotelogin unknown "systemsetup が読めない（管理者権限が要る）" ;;
esac

# ---- 3. 電源 ------------------------------------------------------------------
if [ "$SKIP_POWER" = 1 ]; then
  report power skipped
else
  custom="$(pmset -g custom)"
  power_ok=1
  for kv in "sleep 0" "disksleep 0" "autorestart 1"; do
    k="${kv% *}"; v="${kv#* }"
    # AC / Battery の全セクションで一致していること（値が出ないキーは不一致扱い）
    n_all="$(echo "$custom" | awk -v k="$k" '$1==k {n++} END {print n+0}')"
    n_ok="$(echo "$custom" | awk -v k="$k" -v v="$v" '$1==k && $2==v {n++} END {print n+0}')"
    [ "$n_all" -gt 0 ] && [ "$n_all" = "$n_ok" ] || power_ok=0
  done
  if [ "$power_ok" = 1 ]; then report power unchanged
  elif [ "$DRY_RUN" = 1 ]; then report power changed "(dry-run) pmset -a sleep 0 disksleep 0 autorestart 1"
  elif sudo pmset -a sleep 0 disksleep 0 autorestart 1; then report power changed
  else report power failed "pmset が失敗"; pending "pmset -a sleep 0 disksleep 0 autorestart 1 を手で流す（ノートは autorestart 非対応のことがある）"
  fi
fi

# ---- 4. 自動ログイン -----------------------------------------------------------
if [ "$SKIP_AUTOLOGIN" = 1 ]; then
  report autologin skipped
else
  al="$(root_read sysadminctl -autologin status 2>&1 || true)"
  case "$al" in
    *"Automatic login user: ${USER}"*) report autologin unchanged ;;
    *"Automatic login"*|*"disabled"*|*"off"*)
      if [ "$DRY_RUN" = 1 ]; then report autologin changed "(dry-run) sysadminctl -autologin set -userName ${USER}"
      else
        echo "自動ログインを ${USER} で有効にする（${USER} のパスワードを聞かれる。FileVault はオフが前提）"
        if sudo sysadminctl -autologin set -userName "$USER"; then report autologin changed
        else report autologin failed; pending "自動ログインを手で有効にする: System Settings → ユーザとグループ → 自動ログイン"
        fi
      fi ;;
    *) report autologin unknown "sysadminctl が読めない（管理者権限が要る）" ;;
  esac
fi

# ---- 5. Brewfile ------------------------------------------------------------------
if brew bundle check --file="$BREWFILE" >/dev/null 2>&1; then
  report brew unchanged
elif [ "$DRY_RUN" = 1 ]; then
  report brew changed "(dry-run) brew bundle --file=${BREWFILE}"
else
  echo "brew bundle を流す（Tailscale の pkg が sudo を求めることがある）"
  if brew bundle --file="$BREWFILE"; then report brew changed
  else report brew failed; pending "brew bundle --file=${BREWFILE} を手で流す（失敗時は pgrep -f brew.rb で残存プロセスを確認）"
  fi
fi

# ---- 6. Claude Code CLI ---------------------------------------------------------------
NODE_DIR="$(dirname "$NODE_BIN")"
if [ -x "${NODE_DIR}/claude" ]; then
  report claude-cli unchanged "${NODE_DIR}/claude"
elif [ "$DRY_RUN" = 1 ]; then
  report claude-cli changed "(dry-run) npm install -g @anthropic-ai/claude-code"
elif mise exec node -- npm install -g @anthropic-ai/claude-code; then
  report claude-cli changed
else
  report claude-cli failed; pending "mise exec node -- npm install -g @anthropic-ai/claude-code を手で流す"
fi

# ---- 7. GUI でしかできない残り（判定だけ） ------------------------------------------------------
# リモートユーザーの FDA: sshd 経由で dotfiles の実体（CloudStorage 配下）が読めるか。ssh 自体が通らなければ unknown
if ssh -o BatchMode=yes -o ConnectTimeout=5 localhost true >/dev/null 2>&1; then
  out="$(ssh -o BatchMode=yes localhost 'cat ~/.zshrc' 2>&1 | head -c 200 || true)"
  if echo "$out" | grep -q -i 'not permitted'; then
    report fda failed "sshd から ~/.zshrc の実体が読めない"
    pending "System Settings → 一般 → 共有 → リモートログイン の (i) →「リモートユーザーにフルディスクアクセスを許可」を ON"
  else
    report fda ok
  fi
else
  report fda unknown "ssh localhost が通らない（リモートログインが off か、自分の公開鍵が authorized_keys に無い）"
  pending "ssh -o BatchMode=yes localhost true が通るようにしてから FDA を確認する"
fi

# Tailscale: CLI は PATH → アプリ内の順で解決（非対話 bash なので .zshrc に頼らない）
TS="$(command -v Tailscale 2>/dev/null || true)"
[ -n "$TS" ] || { [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ] && TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale; }
if [ -z "$TS" ]; then
  report tailscale failed "Tailscale が無い"
  pending "Tailscale をインストール（Brewfile の cask 'tailscale-app'）"
else
  dns="$("$TS" status --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("Self",{}).get("DNSName",""))' 2>/dev/null || true)"
  if [ -n "$dns" ]; then
    report tailscale ok "DNSName=${dns%.}"
    pending "（確認のみ）管理画面 https://login.tailscale.com/admin/machines で ${dns%%.*} の Disable key expiry が済んでいること"
  else
    report tailscale failed "ログインしていない（status に Self.DNSName が無い）"
    pending "open -a Tailscale → Sign in（GUI）→ 管理画面で Disable key expiry"
  fi
fi

# authorized_keys: アプリの鍵（コメント mobile-ide）が 1 行以上
n_keys="$(grep -c ' mobile-ide$' "${HOME}/.ssh/authorized_keys" 2>/dev/null || true)"
n_keys="${n_keys:-0}"
if [ "$n_keys" -ge 1 ]; then
  report authorized_keys ok "mobile-ide の鍵 ${n_keys} 件"
else
  report authorized_keys failed "mobile-ide の鍵が無い"
  pending "アプリの設定画面「公開鍵をコピー」→ ~/.ssh/authorized_keys に追記（VERIFY.md 接続設定と鍵）"
fi

# ---- まとめ --------------------------------------------------------------------------------
echo "changed=${CHANGED}"
if [ ${#PENDING[@]} -gt 0 ]; then
  echo "人が続きをやること:"
  for p in "${PENDING[@]}"; do echo "  - ${p}"; done
fi
