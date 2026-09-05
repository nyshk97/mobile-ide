# mobile-ide

iPhone から Mac mini（開発中は MacBook Air）に SSH 接続し、tmux 上のターミナル・Claude Code・Codex を操作する iOS アプリ。設計・構成は [README.md](README.md)、動作確認は [VERIFY.md](VERIFY.md)、各段階の計画は `docs/plans/` を参照。

## 動作確認の癖

- **自走検証を環境変数の上書きだけで回すと、設定の保存・復元の経路を一度も通らない**: このアプリの自走検証は `MOBILE_IDE_HOST` / `MOBILE_IDE_USER` などで接続先を注入して起動する。この上書きは**保存しない**設計（`ConnectionSettings` の init は override を優先するが didSet を通らない）なので、上書き起動ばかりで検証していると「設定画面で入力 → UserDefaults に保存 → 通常起動で復元」の経路を一度も踏まない。実際、接続設定が未保存のまま実機の通常起動でプロジェクト一覧が丸ごと出ない事故があった（自走は全部上書き起動で PASS していた）。**上書き注入とは別に、注入なしで起動して保存値だけで動く経路を最低一度は通す**（`MOBILE_IDE_HOST` 等を付けずに起動して `HOME settings ... configured=true` と `PROJECTS loaded` が出るか）。実機に設定を焼き込むときの `MOBILE_IDE_SAVE_SETTINGS=1` は、UserDefaults を横から書くのではなく setter（= 手入力と同じ didSet）を呼ぶ実装にしてあり、これ自体が保存経路の検証になる。

## ホスト側の癖

- **tmux 内の新しいシェルだけ `.zshrc` が効かない（素のプロンプト・mise / starship が `Operation not permitted`）ときは、tmux サーバーが TCC のアクセスを失っている**: サーバーは 1 つで新しいシェルは全部そこから fork されるので、サーバーが `~/Library/CloudStorage`（dotfiles の実体）を読めないと以後の全セッションが素の zsh になる。sshd や Terminal から直接読めていても関係ないし、アプリの接続設定やリモートログインの FDA 設定を疑っても直らない。切り分けは別ソケットで新サーバーを立てて読めるか（VERIFY.md のホスト → 確認）。直すには `tmux kill-server` でサーバーを作り直す（全セッションが消えるので、中の Claude Code は `--resume` 用の ID を控えてから）。2026-09-05 に実例
