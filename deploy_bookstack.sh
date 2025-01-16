# !/bin/bash

# deploy_bookstack.sh
# A script to automate the deployment of BookStack using Docker and Docker Compose.

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

STATIC_IP=$(prompt "Server Static IP Address (e.g., 172.16.1.146)" "172.16.1.146")
APP_URL="http://$STATIC_IP"  # Using HTTP initially; you can switch to HTTPS later
MYSQL_ROOT_PASSWORD=$(prompt "MySQL Root Password" "rootpassword")
MYSQL_DATABASE=$(prompt "MySQL Database Name" "bookstack")
MYSQL_USER=$(prompt "MySQL Username" "bookstack_user")
MYSQL_PASSWORD=$(prompt "MySQL User Password" "rxhhyundD(254J#!")
PMA_PASSWORD=$(prompt "phpMyAdmin Password" "S*26)Q\$H3Dd1Dmp")

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
APP_URL="$APP_URL"
APP_KEY=""

DB_CONNECTION="mysql"
DB_HOST="db"
DB_PORT="3306"
DB_DATABASE="$MYSQL_DATABASE"
DB_USERNAME="$MYSQL_USER"
DB_PASSWORD="$MYSQL_PASSWORD"

MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"

PMA_HOST="db"
PMA_USER="root"
PMA_PASSWORD="$PMA_PASSWORD"

LDAP_ENABLED="$LDAP_ENABLED"
LDAP_HOST="$LDAP_HOST"
LDAP_PORT="$LDAP_PORT"
LDAP_BASE_DN="$LDAP_BASE_DN"
LDAP_USERNAME="$LDAP_USERNAME"
LDAP_PASSWORD="$LDAP_PASSWORD"

MAIL_DRIVER="smtp"
MAIL_HOST="mailhog"
MAIL_PORT="1025"
EOL

echo ".env file created."

# 3. Create necessary directories
echo "Setting up directories..."

mkdir -p nginx/conf.d
mkdir -p nginx/log
mkdir -p certs
mkdir -p src

echo "Directories are set."

# 4. Create Nginx configuration
echo "Creating Nginx configuration..."

cat > nginx/conf.d/bookstack.conf <<EOL
server {
    listen 80;
    server_name $STATIC_IP;

    location / {
        proxy_pass http://app:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Uncomment the following block if you decide to enable HTTPS later
    # listen 443 ssl;
    # ssl_certificate /etc/nginx/certs/fullchain.pem;
    # ssl_certificate_key /etc/nginx/certs/privkey.pem;
    # ssl_protocols TLSv1.2 TLSv1.3;
    # ssl_ciphers HIGH:!aNULL:!MD5;
}
EOL

echo "Nginx configuration created."

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
      DB_HOST: "\${DB_HOST}"
      DB_PORT: "\${DB_PORT}"
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
      MYSQL_DATABASE: "\${MYSQL_DATABASE}"
      MYSQL_USER: "\${MYSQL_USER}"
      MYSQL_PASSWORD: "\${MYSQL_PASSWORD}"
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
      # - "443:443"  # Uncomment if you enable HTTPS
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./certs:/etc/nginx/certs
      - ./src:/var/www/html
    networks:
      - bookstack_network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: bookstack_phpmyadmin
    restart: unless-stopped
    environment:
      PMA_HOST: "\${PMA_HOST}"
      PMA_USER: "\${PMA_USER}"
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
RUN apt-get update && apt-get install -y \
    libonig-dev \
    libxml2-dev \
    libldap2-dev \
    libexif-dev \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    unzip \
    git \
    curl \
    libzip-dev \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
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

# 8. (Optional) Generate Self-Signed SSL Certificates
# Commented out since we're using HTTP initially. Uncomment if you wish to use HTTPS now.
# echo "Generating self-signed SSL certificates..."

# if [ ! -f certs/fullchain.pem ] || [ ! -f certs/privkey.pem ]; then
#     openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
#         -keyout certs/privkey.pem \
#         -out certs/fullchain.pem \
#         -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=$STATIC_IP"
#     echo "Self-signed SSL certificates generated."
# else
#     echo "SSL certificates already exist. Skipping generation."
# fi

# 9. Set Permissions
echo "Setting file permissions..."

# Ensure the script is run with sufficient permissions or adjust as needed
chown -R "$USER":"$USER" src
chmod -R 755 src

echo "Permissions set."

# 10. Build and Start Docker Containers
echo "Building and starting Docker containers..."

docker-compose up --build -d

echo "Docker containers are up and running."

# 11. Generate Laravel APP_KEY
echo "Generating Laravel APP_KEY..."

# Generate the key and capture it
APP_KEY=$(docker-compose exec app php artisan key:generate --show)

# Update .env with the generated APP_KEY
sed -i "s/^APP_KEY=.*/APP_KEY=$APP_KEY/" .env

# Restart the app container to apply the APP_KEY
docker-compose restart app

echo "Laravel APP_KEY generated and updated in .env."

# 12. Run Laravel Artisan Commands
echo "Running Laravel Artisan commands..."

docker-compose exec app php artisan migrate --force
docker-compose exec app php artisan config:cache
docker-compose exec app php artisan route:cache
docker-compose exec app php artisan view:cache

echo "Laravel Artisan commands executed."

# 13. Final Instructions
echo "=== Deployment Completed ==="
echo "You can access your BookStack application at: $APP_URL"
echo "phpMyAdmin is available at: http://$STATIC_IP:8080"
echo "Default Admin Credentials (change immediately):"
echo "Email: admin@admin.com"
echo "Password: password"

echo "To change the admin credentials, access the phpMyAdmin interface or run Laravel commands within the container."

echo "Note: If you decide to enable HTTPS later, ensure to update the Nginx configuration and regenerate SSL certificates accordingly."
