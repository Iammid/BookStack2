#!/bin/bash

# deploy_bookstack.sh
# A script to automate the deployment of BookStack using Docker and Docker Compose with Let's Encrypt.

set -e

# Function to prompt for input with a default value
prompt() {
    local PROMPT_MESSAGE=$1
    local DEFAULT_VALUE=$2
    read -p "$PROMPT_MESSAGE [$DEFAULT_VALUE]: " INPUT
    echo "${INPUT:-$DEFAULT_VALUE}"
}

echo "=== BookStack Deployment Script ==="

# 1. Prompt for necessary variables
echo "Please provide the following configuration details:"

DOMAIN=$(prompt "Domain Name (e.g., bookstack.yourdomain.com)" "bookstack.example.com")
EMAIL=$(prompt "Email for Let's Encrypt notifications" "admin@example.com")
MYSQL_ROOT_PASSWORD=$(prompt "MySQL Root Password" "rootpassword")
MYSQL_DATABASE=$(prompt "MySQL Database Name" "bookstack")
MYSQL_USER=$(prompt "MySQL Username" "bookstack_user")
MYSQL_PASSWORD=$(prompt "MySQL User Password" "securepassword")
PMA_PASSWORD=$(prompt "phpMyAdmin Password" "securePMApassword")

# LDAP variables are skipped as per your request
LDAP_ENABLED="false"
LDAP_HOST=""
LDAP_PORT=""
LDAP_BASE_DN=""
LDAP_USERNAME=""
LDAP_PASSWORD=""

# 2. Create .env file
echo "Creating .env file..."

cat > .env <<EOL
APP_URL=https://$DOMAIN

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=$MYSQL_DATABASE
DB_USERNAME=$MYSQL_USER
DB_PASSWORD=$MYSQL_PASSWORD

MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD

PMA_HOST=db
PMA_USER=root
PMA_PASSWORD=$PMA_PASSWORD

LDAP_ENABLED=$LDAP_ENABLED
LDAP_HOST=$LDAP_HOST
LDAP_PORT=$LDAP_PORT
LDAP_BASE_DN=$LDAP_BASE_DN
LDAP_USERNAME=$LDAP_USERNAME
LDAP_PASSWORD=$LDAP_PASSWORD

MAIL_DRIVER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
EOL

echo ".env file created."

# 3. Create necessary directories
echo "Setting up directories..."

mkdir -p nginx/conf.d
mkdir -p nginx/log
mkdir -p certbot/www
mkdir -p certbot/conf
mkdir -p src

echo "Directories are set."

# 4. Create Nginx configuration for reverse proxy
echo "Creating Nginx reverse proxy configuration..."

cat > nginx/conf.d/bookstack.conf <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root /var/www/html/public;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

echo "Nginx reverse proxy configuration created."

# 5. Create docker-compose.yml if not present
if [ ! -f docker-compose.yml ]; then
    echo "Creating docker-compose.yml..."

    cat > docker-compose.yml <<EOL
version: '3.8'

services:
  app:
    build: .
    image: bookstack_app
    container_name: bookstack_app
    restart: unless-stopped
    environment:
      APP_URL: "\${APP_URL}"
      DB_HOST: db
      DB_PORT: 3306
      DB_DATABASE: "\${DB_DATABASE}"
      DB_USERNAME: "\${DB_USERNAME}"
      DB_PASSWORD: "\${DB_PASSWORD}"
      APP_KEY: "\${APP_KEY}"
    volumes:
      - ./src:/var/www/html
      - ./php.ini:/usr/local/etc/php/conf.d/custom.ini
    networks:
      - bookstack_network

  db:
    image: mysql:8.0
    container_name: bookstack_db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "\${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "\${DB_DATABASE}"
      MYSQL_USER: "\${DB_USERNAME}"
      MYSQL_PASSWORD: "\${DB_PASSWORD}"
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - bookstack_network

  nginx:
    image: nginx:latest
    container_name: bookstack_nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
      - ./src:/var/www/html
    depends_on:
      - app
    networks:
      - bookstack_network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: bookstack_phpmyadmin
    restart: unless-stopped
    environment:
      PMA_HOST: db
      PMA_USER: root
      PMA_PASSWORD: "\${PMA_PASSWORD}"
    ports:
      - "8080:80"
    networks:
      - bookstack_network

  mailhog:
    image: mailhog/mailhog
    container_name: bookstack_mailhog
    restart: unless-stopped
    ports:
      - "1025:1025"
      - "8025:8025"
    networks:
      - bookstack_network

  certbot:
    image: certbot/certbot
    container_name: certbot
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    entrypoint: /bin/sh -c 'trap exit TERM; while :; do sleep 12h & wait \$${!}; done;'

networks:
  bookstack_network:
    driver: bridge

volumes:
  db_data:
EOL

    echo "docker-compose.yml created."
else
    echo "docker-compose.yml already exists. Skipping creation."
fi

# 6. Create Dockerfile if not present
if [ ! -f Dockerfile ]; then
    echo "Creating Dockerfile..."

    cat > Dockerfile <<EOL
FROM php:8.1-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    libonig-dev \\
    libxml2-dev \\
    libldap2-dev \\
    libexif-dev \\
    libfreetype6-dev \\
    libjpeg62-turbo-dev \\
    libpng-dev \\
    unzip \\
    git \\
    curl \\
    libzip-dev \\
    zip \\
    openssl \\
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \\
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip ldap

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy existing application directory contents
COPY . /var/www/html

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader

# Set permissions
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Expose port 9000 and start php-fpm server
EXPOSE 9000
CMD ["php-fpm"]
EOL

    echo "Dockerfile created."
else
    echo "Dockerfile already exists. Skipping creation."
fi

# 7. Create php.ini
echo "Creating php.ini..."

cat > php.ini <<EOL
memory_limit = 256M
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 300
EOL

echo "php.ini created."

# 8. Obtain SSL Certificates with Certbot
echo "Obtaining SSL certificates with Certbot..."

docker-compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email $EMAIL --agree-tos --no-eff-email -d $DOMAIN

echo "SSL certificates obtained."

# 9. Reload Nginx to Apply SSL Certificates
echo "Reloading Nginx to apply SSL certificates..."

docker-compose exec nginx nginx -s reload

echo "Nginx reloaded."

# 10. Set Permissions
echo "Setting file permissions..."

# Ensure the script is run with sufficient permissions or adjust as needed
sudo chown -R "$USER":"$USER" src
chmod -R 755 src

echo "Permissions set."

# 11. Build and Start Docker Containers
echo "Building and starting Docker containers..."

docker-compose up --build -d

echo "Docker containers are up and running."

# 12. Generate Laravel APP_KEY
echo "Generating Laravel APP_KEY..."

# Generate the key and capture it
APP_KEY=$(docker-compose exec app php artisan key:generate --show)

# Update .env with the generated APP_KEY
sed -i "s/^APP_KEY=.*/APP_KEY=$APP_KEY/" .env

# Ensure the container has the updated APP_KEY
docker-compose exec app bash -c "echo \"APP_KEY=$APP_KEY\" >> .env"

echo "Laravel APP_KEY generated and updated in .env."

# 13. Run Laravel Artisan Commands
echo "Running Laravel Artisan commands..."

docker-compose exec app php artisan migrate --force
docker-compose exec app php artisan config:cache
docker-compose exec app php artisan route:cache
docker-compose exec app php artisan view:cache

echo "Laravel Artisan commands executed."

# 14. Set Up Automatic SSL Renewal
echo "Setting up automatic SSL certificate renewal..."

# Create a renewal script
cat > renew_certificates.sh <<EOL
#!/bin/bash
docker-compose run --rm certbot renew
docker-compose exec nginx nginx -s reload
EOL

chmod +x renew_certificates.sh

# Schedule the renewal script via cron (runs twice daily)
(crontab -l 2>/dev/null; echo "0 0,12 * * * /bin/bash $(pwd)/renew_certificates.sh >> $(pwd)/certbot/renew.log 2>&1") | crontab -

echo "Automatic SSL certificate renewal scheduled via cron."

# 15. Final Instructions
echo "=== Deployment Completed ==="
echo "You can access your BookStack application at: https://$DOMAIN"
echo "phpMyAdmin is available at: http://$DOMAIN:8080"
echo "Default Admin Credentials (change immediately):"
echo "Email: admin@admin.com"
echo "Password: password"

echo "To change the admin credentials, access the phpMyAdmin interface or run Laravel commands within the container."

echo "SSL is set up with Let's Encrypt certificates. They will renew automatically."

