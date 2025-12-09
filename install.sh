#!/bin/bash

set -e

echo "========== Pterodactyl Panel Interactive Installer =========="
echo ""

# Ask for domain
read -p "Enter your panel domain (example: panel.example.com): " PANEL_DOMAIN

# Ask for email (for Let's Encrypt)
read -p "Enter your email for SSL certificate registration: " SSL_EMAIL

PUBLIC_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")

echo ""
echo "==================== CLOUDFLARE DNS SETUP ===================="
echo "Create this record in Cloudflare BEFORE continuing:"
echo ""
echo "TYPE : A"
echo "NAME : ${PANEL_DOMAIN}"
echo "VALUE: ${PUBLIC_IP}"
echo "TTL  : Auto"
echo "PROXY: OFF (DNS only, grey cloud)"
echo ""
echo "If your Wings / node IP is different, use that as VALUE."
echo ""
read -p "After creating the DNS record and waiting ~1–2 minutes, press ENTER to continue..."

echo ""
echo "========== Installing Dependencies =========="
apt update -y
apt install -y software-properties-common curl unzip nginx mariadb-server certbot python3-certbot-nginx git
add-apt-repository ppa:ondrej/php -y
apt update -y
apt install -y php8.2 php8.2-cli php8.2-fpm php8.2-mysql php8.2-zip php8.2-gd php8.2-mbstring php8.2-curl php8.2-xml php8.2-bcmath php8.2-intl php8.2-redis

echo ""
echo "========== Installing Pterodactyl Panel =========="
mkdir -p /home/container/panel
cd /home/container/panel

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz

chmod -R 775 storage/* bootstrap/cache/
cp .env.example .env

php artisan key:generate --force

# Simple local MariaDB setup
mysql -u root -e "CREATE DATABASE IF NOT EXISTS pteropanel; \
  CREATE USER IF NOT EXISTS 'ptero'@'localhost' IDENTIFIED BY 'ptero'; \
  GRANT ALL PRIVILEGES ON pteropanel.* TO 'ptero'@'localhost'; \
  FLUSH PRIVILEGES;"

# Configure .env
sed -i "s#APP_URL=.*#APP_URL=https://${PANEL_DOMAIN}#" .env
sed -i "s#DB_HOST=.*#DB_HOST=localhost#" .env
sed -i "s#DB_DATABASE=.*#DB_DATABASE=pteropanel#" .env
sed -i "s#DB_USERNAME=.*#DB_USERNAME=ptero#" .env
sed -i "s#DB_PASSWORD=.*#DB_PASSWORD=ptero#" .env

php artisan migrate --force

echo ""
echo "========== Generating initial nginx (HTTP only) =========="
# Use a simple HTTP-only config first so certbot can validate on port 80
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

# Start php-fpm and nginx for challenge
service php8.2-fpm start >/dev/null 2>&1 || true
nginx || true

echo ""
echo "========== Requesting SSL Certificate (Let's Encrypt) =========="
certbot certonly --webroot -w /home/container/panel/public -d "${PANEL_DOMAIN}" \
  --email "${SSL_EMAIL}" --agree-tos --non-interactive || {
    echo "!!! SSL generation failed. Check DNS/ports and try reinstalling later."
}

echo ""
echo "========== Switching nginx to full HTTPS config =========="
# Use template with SSL
if [ -f "/home/container/runtime/installer/nginx.conf.template" ]; then
  sed "s/DOMAIN_PLACEHOLDER/${PANEL_DOMAIN}/g" /home/container/runtime/installer/nginx.conf.template > /etc/nginx/sites-enabled/ptero.conf
fi

nginx -s reload || true
nginx -s stop || true

echo ""
echo "========== Installation Finished =========="
echo "Your panel should be available at: https://${PANEL_DOMAIN}"
echo "Now create the admin user by running: php artisan p:user:make (inside the container console)."
touch /home/container/.installed
