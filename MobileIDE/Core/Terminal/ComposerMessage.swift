import Foundation

/// チャット入力欄（composer）の本文を PTY に流すバイト列にする。
///
/// - 常に bracketed paste（`ESC[200~ … ESC[201~`）で包む。相手アプリのモードは読まない。アプリが attach する tmux は
///   クライアント端末に対して常に bracketed paste を有効にし、ペインのモードに応じて包みを剥がす / 通すのを代行する
///   （2026-09-06 に tmux 3.7c で実測）。1 行でも包むのは、Claude Code に「貼り付け」として渡して改行の解釈をぶらさないため
/// - 改行は `\r` にする（実端末の貼り付けや `tmux paste-buffer` と同じ形。Codex / Claude Code はこれで 1 入力として受ける）。
///   `\r\n` は 1 つの `\r`
/// - 末尾の改行は落とす（return を押してから送信、で空行を送らない）
/// - `ESC`（0x1b）は落とす（本文に `ESC[201~` があると包みを途中で閉じられる。端末ログの貼り付けで起きる）
/// - Enter（`\r`）は包みの**外**に付ける（中に入れると改行として入力欄に残る）
/// - 本文が空（改行だけ）なら空の Data を返す。呼び出し側は送らない
enum ComposerMessage {
    static let pasteStart: [UInt8] = Array("\u{1b}[200~".utf8)
    static let pasteEnd: [UInt8] = Array("\u{1b}[201~".utf8)
    static let enter: UInt8 = 0x0d

    static func bytes(for text: String) -> Data {
        let body = normalizedBody(text)
        guard !body.isEmpty else { return Data() }
        return Data(pasteStart + body + pasteEnd + [enter])
    }

    /// 包みの中身。ESC の除去 → 改行を `\r` に統一 → 末尾の改行を除去
    static func normalizedBody(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        var previousWasCR = false
        for byte in text.utf8 {
            switch byte {
            case 0x1b:
                continue
            case 0x0d:
                out.append(0x0d)
                previousWasCR = true
                continue
            case 0x0a:
                if !previousWasCR { out.append(0x0d) }
            default:
                out.append(byte)
            }
            previousWasCR = false
        }
        while out.last == 0x0d { out.removeLast() }
        return out
    }
}
