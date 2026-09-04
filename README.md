# mobile-ide

iPhone から Mac mini に接続し、tmux 上のターミナル・Claude Code・Codex を操作する iOS アプリ。

## 背景

- Mac mini を 24 時間 / 365 日起動させ、どこからでも開発環境として使えるようにしたい
- 常用端末は折りたたみ iPhone（内側画面 7.8 インチ前後、4:3 に近い比率）を想定
- PC では自作 IDE の [PolePole](https://github.com/nyshk97/ide) を使っている。スマホでも「プロジェクトを選んで端末を開き、Claude Code に頼む」までの動線を同じ感覚で辿りたい
- Claude Code 公式の Remote Control は便利だが、bypass permissions が使えない・`/resume` などターミナル専用コマンドが使えない・Claude の外の素のシェル操作ができない、という制約がある。これらを SSH 経由で補う

## 実現したいこと

- iPhone を開いて、Mac mini の既存プロジェクトで Claude Code / Codex に 1 タスク頼み、結果を見て閉じる、が完結する
- アプリを閉じても Mac mini 側のセッションは生き続け、次に開いたときに続きが見える
- 写真やスクショを Claude に渡せる
- PolePole でピン留めしているプロジェクト一覧をそのまま使い、管理を二重化しない
- iPhone から新規 Claude Code（Codex）セッションを作成できる
- iPhone で作った新規 Claude Code（Codex）セッションを、Mac mini 内の PolePole 等のアプリから再開できる
- Mac mini 内の PolePole 等のアプリで作った Claude Code（Codex）セッションを、iPhone から再開できる

## 構成（案）

```
iPhone アプリ                          Mac mini
┌──────────────────────┐              ┌──────────────────────────┐
│ SwiftTerm (端末画面)  │◄─ PTY ch ───►│ tmux attach -t <project> │
│ プロジェクト一覧      │◄─ exec ch ──►│ cat projects.json 等      │
│ 画像添付             │── SFTP ch ──►│ ~/.claude/uploads/       │
│        ↑ Citadel (SSH client, 1 接続に複数チャネル)              │
└──────────┼───────────┘              └──────────────────────────┘
           │ Tailscale (WireGuard)。両端が 100.x.x.x を持つ
           ▼
   iPhone の Tailscale アプリが VPN として常駐
```

- **ネットワーク**: Tailscale。マンション一括回線でポート開放できない前提。iPhone 側は Tailscale アプリを VPN として入れるだけで、本アプリは何も知らない
- **トランスポート**: SSH（Mac mini のリモートログイン）。ed25519 鍵をアプリ内で生成し、公開鍵を `authorized_keys` に登録する。パスワード認証は切る
- **SSH クライアント**: [Citadel](https://github.com/orlandos-nl/Citadel)（SwiftNIO SSH ベース。exec / PTY / SFTP を 1 接続で多重化）
- **端末エミュレータ**: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)。将来 libghostty の iOS ターゲットに差し替えられるよう protocol の裏に隠す
- **セッション永続化**: tmux。SSH が切れても Mac mini 側でプロセスを生かす層。ユーザーに tmux のキーバインドは見せない（アプリが `tmux new-session -A` を流すだけ）
- **プロジェクト一覧**: PolePole の `~/Library/Application Support/polepole/projects.json` を exec で読む。`tmux list-sessions` と突き合わせて作業中のものにマークを付ける

### Mac mini 側の前提

- 自動ログイン有効（Claude Code の資格情報がログインキーチェーンにあるため。FileVault はオフになる）
- `pmset -a sleep 0 disksleep 0 autorestart 1`
- リモートログイン有効 + 「リモートユーザーにフルディスクアクセスを許可」（dotfiles が `~/Library/CloudStorage/` 配下にあり、sshd から `.zshrc` を読むのに必要）
- SSH の exec チャネルは `.zshrc` を読まないので、アプリ側で `PATH=/opt/homebrew/bin:...` を前置きしてからコマンドを流す。端末経路（tmux 内の対話シェル）は影響を受けない

## MVP（案）

ゴール: 「iPhone を開いて、Mac mini の既存プロジェクトで Claude Code に 1 タスク頼み、結果を見て閉じる」が完結する。

### 入れるもの

1. **接続設定**: ホスト名（Tailscale の MagicDNS 名）、ユーザー名、ed25519 鍵の生成と公開鍵の表示。接続先は 1 台固定
2. **プロジェクト一覧**: `projects.json` を読んで PolePole のピン順で表示。`tmux list-sessions` と突き合わせ、生きているセッションがある行にマーク
3. **セッションを開く**: タップで PTY チャネルを開き `tmux new-session -A -s <name> -c <path>` を流す。初回も 2 回目も同じコマンド
4. **端末画面**: SwiftTerm 1 枚 + キーボードバー（Esc / Ctrl / Tab / 矢印 4 方向 / Shift+Tab / Enter）。Ctrl はトグルで次の 1 キーに乗せる。日本語入力は確定後にだけ送る
5. **再接続**: フォアグラウンド復帰時と回線エラー時に、黙って SSH を張り直して同じ tmux セッションに attach し直す
6. **画像添付**: 写真ピッカーで選び、SFTP で `~/.claude/uploads/` に置き、`@<path> ` を端末に流し込む

### 意図的に外すもの

- diff 表示と push 通知（Claude アプリの Remote Control が持っている。tmux 内で `claude --rc` を動かせば同じセッションを Claude アプリで開ける）
- tmux の window 管理 UI
- ファイルブラウザ、git バッジ、MRU、Cmd+P 相当
- 複数ホスト、設定同期、テーマ
- Mac mini 側の常駐デーモン（SSH ポーリングで足りている間は不要）

## 開発

XcodeGen + mise。`.xcodeproj` は生成物（gitignore 対象）。

```sh
mise run gen          # project.yml → MobileIDE.xcodeproj
mise run run          # シミュレータで build → install → launch
mise run device-run   # USB 接続した iPhone に build → install → launch
mise run icon         # アプリアイコンを再生成
```

詳細は [VERIFY.md](VERIFY.md)。
