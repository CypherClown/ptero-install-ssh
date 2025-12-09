#!/bin/bash

cd /home/container

mkdir -p runtime

if [ ! -d "runtime/installer" ]; then
    echo "[BOOTSTRAP] Downloading installer..."
    git clone https://github.com/YOUR_GITHUB/YOUR_REPO.git runtime/installer
else
    echo "[BOOTSTRAP] Updating installer..."
    cd runtime/installer
    git pull --ff-only
    cd /home/container
fi

if [ ! -f "/home/container/.installed" ]; then
    echo "[BOOTSTRAP] Running interactive installer..."
    bash runtime/installer/install.sh
fi

echo "[BOOTSTRAP] Starting panel..."
cd /home/container/panel
php artisan queue:work --tries=3 &
nginx -g 'daemon off;'
