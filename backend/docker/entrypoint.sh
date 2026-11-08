#!/bin/sh
set -e

echo "Starting TindaKo backend entrypoint..."

# Ensure required storage and cache directories exist and are writable
mkdir -p /var/www/html/storage/framework/cache/data
mkdir -p /var/www/html/storage/framework/sessions
mkdir -p /var/www/html/storage/framework/views
mkdir -p /var/www/html/storage/logs
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Dynamic Render PORT configuration (defaults to 10000 if unset)
PORT="${PORT:-10000}"
echo "Configuring Nginx to bind on port ${PORT} and port 80..."
if [ -f /etc/nginx/http.d/default.conf ]; then
    sed -i "s/listen 10000;/listen ${PORT};/g" /etc/nginx/http.d/default.conf 2>/dev/null || true
fi

# Run database migrations if requested (safely handle cold-start Neon DB delays)
if [ "$RUN_MIGRATIONS" = "true" ]; then
    echo "Running database migrations..."
    php artisan migrate --force || echo "Warning: migration command failed or database is still waking up."
fi

# Cache config & routes for cloud performance
php artisan config:cache || true
php artisan route:cache || true

# Start PHP-FPM in background with root-master permission flag (-R)
echo "Starting PHP-FPM daemon..."
php-fpm -D -R || php-fpm -D

# Start Nginx in foreground to serve external traffic
echo "Starting Nginx in foreground on port ${PORT}..."
exec nginx -g "daemon off;"
