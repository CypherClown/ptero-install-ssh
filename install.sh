#!/bin/bash
set -e

echo "=============================================================="
echo "              Pterodactyl Panel Interactive Installer         "
echo "=============================================================="
echo ""

# ------------------------------------------
# Ask for domain
# ------------------------------------------
echo "Enter your panel domain (example: panel.example.com):"
read PANEL_DOMAIN

# ------------------------------------------
# Ask for SSL email
# ------------------------------------------
echo "Enter your email for SSL certificate registration:"
read SSL_EMAIL

# ------------------------------------------
# Get server IP
# ------------------------------------------
PUBLIC_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")

echo ""
echo "==================== CLOUDFLARE DNS SETUP ===================="
echo "Create this DNS record in Cloudflare:"
echo ""
echo "TYPE : A"
echo "NAME : ${PANEL_DOMAIN}"
echo "VALUE: ${PUBLIC_IP}"
echo "TTL  : Auto"
echo "PROXY: OFF (DNS only, grey cloud)"
echo ""
echo "AFTER creating DNS record, wait 1–2 minutes."
echo "Press ENTER to continue once DNS is set..."
read

echo ""
echo "=============================================================="
echo "                Installing System Dependencies                "
echo "=============================================================="

apt update -y
apt install -y software-properties-common curl unzip nginx mariadb-server git certbot python3-certbot-nginx

add-apt-repository ppa:ondrej/php -y
apt update -y

apt install -y \
    php8.2 php8.2-cli php8.2-fpm php8.2-mysql php8.2-zip \
    php8.2-gd php8.2-mbstring php8.2-curl php8.2-xml php8.2-bcmath \
    php8.2-intl php8.2-redis

echo ""
echo "=============================================================="
echo "                Installing Pterodactyl Panel                  "
echo "=============================================================="

mkdir -p /home/container/panel
cd /home/container/panel

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz

chmod -R 775 storage/* bootstrap/cache/
cp .env.example .env

php artisan key:generate --force

echo ""
echo "=============================================================="
echo "                    Configuring Database                      "
echo "=============================================================="

mysql -u root -e "
CREATE DATABASE IF NOT EXISTS pteropanel;
CREATE USER IF NOT EXISTS 'ptero'@'localhost' IDENTIFIED BY 'ptero';
GRANT ALL PRIVILEGES ON pteropanel.* TO 'ptero'@'localhost';
FLUSH PRIVILEGES;
"

sed -i "s#APP_URL=.*#APP_URL=https://${PANEL_DOMAIN}#" .env
sed -i "s#DB_DATABASE=.*#DB_DATABASE=pteropanel#" .env
sed -i "s#DB_USERNAME=.*#DB_USERNAME=ptero#" .env
sed -i "s#DB_PASSWORD=.*#DB_PASSWORD=ptero#" .env

php artisan migrate --force

echo ""
echo "=============================================================="
echo "                   Creating Initial nginx Config              "
echo "=============================================================="

cat > /etc/nginx/sites-enabled/ptero.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    root /home/container/panel/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default || true

service php8.2-fpm start >/dev/null 2>&1 || true
nginx || true

echo ""
echo "=============================================================="
echo "                Requesting SSL Certificate (LE)               "
echo "=============================================================="

certbot certonly --webroot -w /home/container/panel/public -d "${PANEL_DOMAIN}" \
 --email "${SSL_EMAIL}" --agree-tos --non-interactive || {
    echo ""
    echo "!!! SSL generation FAILED."
    echo "Check DNS, port 80 accessibility, PROXY OFF in Cloudflare."
    echo "You can re-run installation by deleting /home/container/.installed"
    echo "=============================================================="
}

echo ""
echo "=============================================================="
echo "               Switching nginx to HTTPS mode                  "
echo "=============================================================="

if [ -f "/home/container/runtime/installer/nginx.conf.template" ]; then
  sed "s/DOMAIN_PLACEHOLDER/${PANEL_DOMAIN}/g" \
      /home/container/runtime/installer/nginx.conf.template \
      > /etc/nginx/sites-enabled/ptero.conf
fi

nginx -s reload || true
nginx -s stop || true

echo ""
echo "=============================================================="
echo "                     Installation Complete                    "
echo "=============================================================="
echo "Panel URL: https://${PANEL_DOMAIN}"
echo ""
echo "To create your first admin account, run this command:"
echo "  php artisan p:user:make"
echo ""
echo "=============================================================="

touch /home/container/.installed
