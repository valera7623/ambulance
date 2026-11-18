#!/bin/bash
# Запускать НА VPS (уже под root), после scp файлов в /var/www/smp-download/
set -euo pipefail

echo "== содержимое /var/www/smp-download =="
ls -lah /var/www/smp-download

echo "== проверка :8088 =="
curl -sS -m 5 -o /tmp/smp-page.html -w "page %{http_code} %{size_download}\n" http://127.0.0.1:8088/
head -c 120 /tmp/smp-page.html; echo
curl -sS -m 5 -o /tmp/smp.apk -w "apk  %{http_code} %{size_download} %{content_type}\n" http://127.0.0.1:8088/app-release.apk
file /tmp/smp.apk
# APK ZIP magic: PK
python3 - <<'PY'
import pathlib
b = pathlib.Path('/tmp/smp.apk').read_bytes()[:4]
print('magic', b)
if b != b'PK\x03\x04' and b != b'PK\x05\x06':
    raise SystemExit('ERROR: /app-release.apk на :8088 — не APK (похоже на HTML/чужой сайт)')
print('OK: на :8088 отдаётся настоящий APK')
PY

echo "== что на :80 /app-release.apk (должен быть ДРУГОЙ проект) =="
curl -sS -m 5 -o /tmp/port80.bin -w "80apk %{http_code} %{size_download} %{content_type}\n" http://127.0.0.1/app-release.apk || true
file /tmp/port80.bin || true
head -c 200 /tmp/port80.bin; echo

echo
echo "Открывать только: http://147.45.236.228:8088/"
echo "APK только:       http://147.45.236.228:8088/app-release.apk"
echo "Без :8088 попадёте на platega.io — это нормально для порта 80, не трогаем."
