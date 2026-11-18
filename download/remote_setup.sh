set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx
mkdir -p /var/www/smp-download
cat > /etc/nginx/sites-available/smp-download <<'NGX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name 147.45.236.228 _;
    root /var/www/smp-download;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location = /app-release.apk {
        default_type application/vnd.android.package-archive;
        add_header Content-Disposition 'attachment; filename="smp-guide.apk"';
    }
}
NGX
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/smp-download /etc/nginx/sites-enabled/smp-download
nginx -t
systemctl enable --now nginx
systemctl reload nginx
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
ss -tlnp | grep -E ':80|:443' || true
ls -la /var/www/smp-download
echo READY_FOR_UPLOAD
