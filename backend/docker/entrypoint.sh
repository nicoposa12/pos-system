#!/bin/sh
set -e

# Run migrations if configured
if [ "$RUN_MIGRATIONS" = "true" ]; then
    echo "Running migrations..."
    php artisan migrate --force
fi

# Cache config & routes
php artisan config:cache || true
php artisan route:cache || true

# Start PHP-FPM in background
php-fpm -D

# Start Nginx in foreground
echo "Starting Nginx..."
exec nginx -g "daemon off;"

