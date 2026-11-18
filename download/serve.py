#!/usr/bin/env python3
"""Раздаёт страницу скачивания APK и QR по Wi‑Fi станции."""

from __future__ import annotations

import argparse
import socket
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APK_NAME = "app-release.apk"


def lan_ip() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def write_qr(svg_path: Path, url: str) -> None:
    try:
        import qrcode
        from qrcode.image.svg import SvgPathImage
    except ImportError as exc:  # pragma: no cover
        raise SystemExit(
            "Нужен пакет qrcode. Установите: python -m pip install qrcode"
        ) from exc

    image = qrcode.make(url, image_factory=SvgPathImage)
    with svg_path.open("wb") as handle:
        image.save(handle)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--apk",
        default=APK_NAME,
        help="Имя APK в этой папке (по умолчанию app-release.apk)",
    )
    args = parser.parse_args()

    apk_path = ROOT / args.apk
    if not apk_path.exists():
        print(
            f"Нет файла {apk_path.name}.\n"
            "Соберите release APK и скопируйте сюда:\n"
            r"  C:\src\ambulance\app\build\app\outputs\flutter-apk\app-release.apk",
            file=sys.stderr,
        )
        print(f"Ожидаемый путь: {apk_path}", file=sys.stderr)
        return 1

    if args.apk != APK_NAME:
        target = ROOT / APK_NAME
        if target.resolve() != apk_path.resolve():
            target.write_bytes(apk_path.read_bytes())

    ip = lan_ip()
    base = f"http://{ip}:{args.port}"
    apk_url = f"{base}/{APK_NAME}"
    write_qr(ROOT / "qr.svg", apk_url)

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(ROOT), **kw)

        def log_message(self, fmt: str, *log_args) -> None:
            sys.stdout.write("[%s] %s\n" % (self.log_date_time_string(), fmt % log_args))

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print("Страница скачивания:")
    print(f"  {base}/")
    print("APK:")
    print(f"  {apk_url}")
    print("QR сохранён в download/qr.svg")
    print("Остановка: Ctrl+C")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nОстановлено.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
