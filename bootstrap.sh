#!/bin/bash
set -e

cd /home/container

# Make sure runtime dir exists
mkdir -p runtime

# Make sure git exists (on some images it might not)
if ! command -v git >/dev/null 2>&1; then
  echo "[BOOTSTRAP] git not found, trying to install (may fail if container is non-root)..."
  apt update -y && apt install -y git || true
fi

# Clone or update installer repo contents
if [ ! -d "runtime/installer/.git" ]; then
  echo "[BOOTSTRAP] Cloning installer repo..."
  rm -rf runtime/installer
  git clone https://github.com/CypherClown/ptero-install-ssh.git runtime/installer
else
  echo "[BOOTSTRAP] Updating installer repo..."
  cd runtime/installer
  git pull --ff-only || true
  cd /home/container
fi

# Run interactive install once
if [ ! -f ".installed" ]; then
  echo "[BOOTSTRAP] Running interactive installer (first time setup)..."
  bash runtime/installer/install.sh
fi

# Basic sanity check
if [ ! -d "panel" ]; then
  echo "[BOOTSTRAP] ERROR: /home/container/panel is missing even after install."
  exit 1
fi

echo "[BOOTSTRAP] Starting services..."

# Start PHP-FPM (ignore error if it's already running or service doesn't exist)
service php8.2-fpm start >/dev/null 2>&1 || true

# Start queue worker in background
cd /home/container/panel
php artisan queue:work --tries=3 &

# Run nginx in foreground so Pterodactyl can track the process
echo "[BOOTSTRAP] Starting nginx in foreground..."
nginx -g 'daemon off;'
