#!/bin/bash

echo "========== Pterodactyl Panel Interactive Installer =========="
echo ""

# Ask for domain
read -p "Enter your panel domain (example: panel.example.com): " PANEL_DOMAIN

# Ask for email (needed for certbot)
read -p "Enter your email for SSL certificate registration: " SSL_EMAIL

echo ""
echo "==================== CLOUDFLARE DNS SETUP ===================="
echo "Create these DNS records in Cloudflare:"
echo ""
echo "TYPE: A"
echo "NAME: ${PANEL_DOMAIN}"
echo "VALUE: $(curl -s ifconfig.me)"
echo "TTL: Auto"
echo "PROXY: OFF (DNS ONLY)"
echo ""
echo "After adding records, wait 1–2 minutes before continuing."
echo ""
read -p "Press ENTER after you add the DNS record..."

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

mysql -u root -e "CREATE DATABASE IF NOT EXISTS pteropanel; CREATE USER IF NOT EXISTS 'ptero'@'localhost' IDENTIFIED BY 'ptero'; GRANT ALL PRIVILEGES ON pteropanel.* TO 'ptero'@'localhost'; FLUSH PRIVILEGES;"

sed -i "s#APP_URL=.*#APP_URL=https://${PANEL_DOMAIN}#" .env
sed -i "s#DB_DATABASE=.*#DB_DATABASE=pteropanel#" .env
sed -i "s#DB_USERNAME=.*#DB_USERNAME=ptero#" .env
sed -i "s#DB_PASSWORD=.*#DB_PASSWORD=ptero#" .env

php artisan migrate --force

echo ""
echo "========== Generating nginx config =========="

sed "s/DOMAIN_PLACEHOLDER/${PANEL_DOMAIN}/g" /home/container/runtime/installer/nginx.conf.template > /etc/nginx/sites-enabled/ptero.conf

rm /etc/nginx/sites-enabled/default || true

systemctl restart nginx

echo ""
echo "========== Generating SSL Certificate =========="
certbot --nginx -d ${PANEL_DOMAIN} --email ${SSL_EMAIL} --agree-tos --non-interactive || {
    echo "SSL failed! Check DNS and try again."
}

echo ""
echo "========== Installation Finished =========="
touch /home/container/.installed
