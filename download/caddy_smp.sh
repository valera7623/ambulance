#!/bin/bash
# Отдаёт /var/www/smp-download с https://smp-guide.com.ru/ самим Caddy.
# Порт 8088 из контейнера ведёт не на эти файлы, поэтому каталог монтируется напрямую.
set -euo pipefail

CADDYFILE=/home/valera/gameforge/Caddyfile
CONTAINER=gameforge-caddy-1
DOMAIN=smp-guide.com.ru
WORKDIR=/home/valera/gameforge
OVERRIDE="${WORKDIR}/docker-compose.smp.yml"
WEBROOT=/var/www/smp-download

if [ ! -f "${WEBROOT}/index.html" ] || [ ! -f "${WEBROOT}/app-release.apk" ]; then
  echo "В ${WEBROOT} нет index.html или app-release.apk"
  exit 1
fi

backup="${CADDYFILE}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$CADDYFILE" "$backup"
echo "Копия: $backup"

cat > "$OVERRIDE" <<'EOF'
services:
  caddy:
    volumes:
      - /var/www/smp-download:/srv/smp:ro
EOF

CADDYFILE="$CADDYFILE" DOMAIN="$DOMAIN" python3 - <<'PY'
import os
from pathlib import Path

source = Path(os.environ["CADDYFILE"])
domain = os.environ["DOMAIN"]
lines = source.read_text().splitlines(keepends=True)

def opens_block(line: str) -> bool:
    stripped = line.strip()
    return stripped.endswith("{") and "{$" not in stripped and "{uri}" not in stripped

kept: list[str] = []
i = 0
while i < len(lines):
    if domain in lines[i] and opens_block(lines[i]):
        depth = lines[i].count("{") - lines[i].count("}")
        i += 1
        while i < len(lines) and depth > 0:
            depth += lines[i].count("{") - lines[i].count("}")
            i += 1
        continue
    kept.append(lines[i])
    i += 1

block = f"""
{domain} {{
	root * /srv/smp
	encode gzip
	header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
	@http protocol http
	redir @http https://{domain}{{uri}} permanent
	file_server
}}
"""
text = "".join(kept).rstrip() + "\n" + block
with source.open("r+") as handle:
    handle.seek(0)
    handle.write(text)
    handle.truncate()
print(block)
PY

echo "Пересоздаю только Caddy, чтобы подключить каталог справочника..."
(
  cd "$WORKDIR"
  # Нельзя экспортировать DOMAIN=smp-guide.com.ru: compose подставит его вместо gameforge.website.
  DOMAIN=gameforge.website docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.smp.yml up -d --no-deps --force-recreate caddy
)

echo "Жду страницу справочника..."
ok=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  sleep 4
  if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
    echo "контейнер ещё запускается"
    continue
  fi
  if docker exec "$CONTAINER" wget -q -O /tmp/smp-check.html -T 10 "https://${DOMAIN}/" \
    && docker exec "$CONTAINER" grep -q "Клинические рекомендации" /tmp/smp-check.html; then
    ok=1
    break
  fi
  echo "ещё нет"
done

if [ "$ok" != 1 ]; then
  echo "Страница справочника не открылась. Последние строки Caddy:"
  docker logs --tail 40 "$CONTAINER" || true
  exit 1
fi

echo "Готово: https://${DOMAIN}/"
