#!/usr/bin/env python3
"""Создаёт qr.svg на фиксированный публичный URL APK."""

from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--url",
        default="https://smp-guide.com.ru/",
        help="Публичная ссылка на APK",
    )
    parser.add_argument(
        "--out",
        default=str(ROOT / "qr.svg"),
        help="Куда сохранить SVG",
    )
    args = parser.parse_args()

    try:
        import qrcode
        from qrcode.image.svg import SvgPathImage
    except ImportError as exc:
        raise SystemExit(
            "Установите пакет: python -m pip install qrcode"
        ) from exc

    out = Path(args.out)
    image = qrcode.make(args.url, image_factory=SvgPathImage)
    with out.open("wb") as handle:
        image.save(handle)
    print(f"QR → {out}")
    print(f"URL → {args.url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
