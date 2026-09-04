"""再接続（#7）の検証用 TCP 中継。アプリを 127.0.0.1:2222 に向け、ここから sshd（22）へ流す。

sshd や authorized_keys に触らずに「回線断」「無音の断」を起こすための道具。

使い方:
  python3 scripts/ssh-proxy.py [--listen 2222] [--target 127.0.0.1:22]

シグナル:
  SIGHUP   今ある接続を全部閉じる（listen は続ける）。TCP が切れる = アプリ側で回線断として見える
  SIGUSR1  凍結トグル。今ある接続の中継を両方向とも止める（ソケットは保つ）。無音の断の再現。
           凍結後に来た新しい接続は普通に中継する（再接続の試行を通すため）。もう一度で解除
  SIGTERM  全部閉じて終了。再接続の試行が connection refused で失敗し続ける（バックオフの確認）

stdout に `PROXY listening` / `PROXY open #n` / `PROXY close #n` / `PROXY drop-all` / `PROXY freeze on|off` を出す。
"""
import asyncio
import signal
import sys


class Proxy:
    def __init__(self, listen_port, target_host, target_port):
        self.listen_port = listen_port
        self.target_host = target_host
        self.target_port = target_port
        self.connections = {}  # id -> (client_writer, upstream_writer)
        self.frozen = set()  # 凍結中の接続 id
        self.next_id = 1

    def log(self, msg):
        print(f"PROXY {msg}", flush=True)

    async def handle(self, reader, writer):
        cid = self.next_id
        self.next_id += 1
        try:
            up_reader, up_writer = await asyncio.open_connection(self.target_host, self.target_port)
        except OSError as e:
            self.log(f"open #{cid} failed {e}")
            writer.close()
            return
        self.connections[cid] = (writer, up_writer)
        self.log(f"open #{cid}")
        try:
            await asyncio.gather(
                self.pump(cid, reader, up_writer),
                self.pump(cid, up_reader, writer),
            )
        finally:
            self.connections.pop(cid, None)
            self.frozen.discard(cid)
            for w in (writer, up_writer):
                try:
                    w.close()
                except Exception:
                    pass
            self.log(f"close #{cid}")

    async def pump(self, cid, reader, writer):
        try:
            while True:
                data = await reader.read(65536)
                # 凍結中は読んだデータも EOF も相手に伝えない（解除まで待つ）。
                # 片側が閉じても反対側のソケットは開いたままなので、sshd と tmux クライアントは生き続ける
                while cid in self.frozen:
                    await asyncio.sleep(0.1)
                if not data:
                    break
                writer.write(data)
                await writer.drain()
        except (ConnectionError, asyncio.CancelledError, OSError):
            pass
        finally:
            try:
                writer.close()
            except Exception:
                pass

    def drop_all(self):
        self.log(f"drop-all ({len(self.connections)})")
        for cid, (w, uw) in list(self.connections.items()):
            for x in (w, uw):
                try:
                    x.transport.abort()
                except Exception:
                    pass

    def toggle_freeze(self):
        if self.frozen:
            self.frozen.clear()
            self.log("freeze off")
        else:
            self.frozen = set(self.connections.keys())
            self.log(f"freeze on ({len(self.frozen)})")

    async def run(self):
        server = await asyncio.start_server(self.handle, "127.0.0.1", self.listen_port)
        loop = asyncio.get_running_loop()
        stop = asyncio.Event()
        loop.add_signal_handler(signal.SIGHUP, self.drop_all)
        loop.add_signal_handler(signal.SIGUSR1, self.toggle_freeze)
        loop.add_signal_handler(signal.SIGTERM, stop.set)
        loop.add_signal_handler(signal.SIGINT, stop.set)
        self.log(f"listening {self.listen_port} -> {self.target_host}:{self.target_port}")
        async with server:
            await stop.wait()
            self.drop_all()
        self.log("exit")


def main(argv):
    listen = 2222
    target = "127.0.0.1:22"
    i = 0
    while i < len(argv):
        if argv[i] == "--listen":
            listen = int(argv[i + 1]); i += 2
        elif argv[i] == "--target":
            target = argv[i + 1]; i += 2
        else:
            sys.exit(f"unknown arg: {argv[i]}")
    host, port = target.rsplit(":", 1)
    asyncio.run(Proxy(listen, host, int(port)).run())


if __name__ == "__main__":
    main(sys.argv[1:])
