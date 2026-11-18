#!/bin/bash
# Запускать на VPS от root, когда A-запись smp-guide.com.ru уже указывает на этот сервер.
# Чужой сайт на порту 80 не перезаписывается: свой блок только для имён домена.
set -euo pipefail

DOMAIN=smp-guide.com.ru
WEBROOT=/var/www/smp-download
SITE=/etc/nginx/sites-available/smp-guide.com.ru
EXPECTED_IP=147.45.236.228

echo "== кто слушает 80 и 443 =="
ss -lntp | grep -E ':80 |:443 ' || true

if ! ss -lntp | grep -q 'nginx'; then
  echo "nginx не запущен. Сначала должен работать уже настроенный nginx (порт 8088)."
  exit 1
fi

if ss -lntp | grep -E ':80 ' | grep -v nginx | grep -q .; then
  echo
  echo "Порт 80 занят не nginx. Сертификат и сайт домена тогда выдаёт та программа,"
  echo "которая уже держит 80 (часто панель: FastPanel, ISPmanager, Hestia)."
  echo "В панели: сайт ${DOMAIN}, каталог ${WEBROOT}, SSL Let's Encrypt."
  echo "Nginx на 80 не переключаю, чтобы не погасить другой проект."
  ss -lntp | grep -E ':80 ' || true
  exit 1
fi

echo "== DNS =="
RESOLVED="$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}')"
echo "${DOMAIN} -> ${RESOLVED:-нет записи}"
if [ "${RESOLVED:-}" != "$EXPECTED_IP" ]; then
  echo "Сначала в DNS домена создайте A-запись @ и www → ${EXPECTED_IP}"
  echo "Подождите, пока команда выше покажет ${EXPECTED_IP}, и запустите скрипт снова."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq certbot python3-certbot-nginx

cat > "$SITE" <<NGX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    root ${WEBROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location = /app-release.apk {
        default_type application/vnd.android.package-archive;
        add_header Content-Disposition 'attachment; filename="smp-guide.apk"';
    }
}
NGX

ln -sfn "$SITE" /etc/nginx/sites-enabled/smp-guide.com.ru
nginx -t
systemctl reload nginx

ufw allow 80/tcp || true
ufw allow 443/tcp || true

CERT_DOMAINS=(-d "$DOMAIN")
WWW_IP="$(getent ahostsv4 "www.${DOMAIN}" | awk '{print $1; exit}')"
if [ "${WWW_IP:-}" = "$EXPECTED_IP" ]; then
  CERT_DOMAINS+=(-d "www.${DOMAIN}")
else
  echo "www.${DOMAIN} пока не указывает на ${EXPECTED_IP} — сертификат только для ${DOMAIN}"
fi

certbot --nginx \
  "${CERT_DOMAINS[@]}" \
  --agree-tos --register-unsafely-without-email \
  --redirect --non-interactive

echo
echo "Готово: https://${DOMAIN}/"
echo "Проверка: curl -I https://${DOMAIN}/"
