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

# Configure
