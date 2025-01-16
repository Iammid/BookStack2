#!/bin/bash

# deploy_bookstack.sh
# A script to automate the deployment of a forked BookStack application using Docker and Docker Compose.

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
APP_URL="https://$STATIC_IP"
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
APP_URL=$APP_URL
APP_KEY=

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
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $STATIC_IP;

    ssl_certificate /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

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

echo "Nginx configuration created."

# 5. Create Dockerfile if not present
if [ ! -f Dockerfile ]; then
    echo "Creating Dockerfile..."

    cat > Dockerfile <<EOL
FROM php:8.1-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    libonig-dev \\
    libxml2-dev \\
    libldap2-dev \\
    unzip \\
    git \\
    curl \\
    libzip-dev \\
    zip \\
    openssl

# Install PHP extensions
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip ldap

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy existing application directory contents
COPY ./src /var/www/html

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

# 6. Organize Codebase
# echo "Organizing codebase..."

# Check if src directory is empty
# if [ -z "$(ls -A src)" ]; then
#    echo "Moving application files to src directory..."
    # Exclude script, docker-compose.yml, Dockerfile, README.md, .env, nginx, certs
#    for file in *; do
#        case "$file" in
#            deploy_bookstack.sh|docker-compose.yml|Dockerfile|README.md|.env|nginx|certs)
#                continue
#                ;;
#            *)
#                if [ -d "$file" ]; then
#                    mv "$file" src/
#                elif [ -f "$file" ]; then
#                    mv "$file" src/
#                fi
#                ;;
#        esac
#    done
# else
#    echo "src directory already contains files. Skipping move."
# fi

# echo "Codebase organized."

# 7. Create Apache Configuration (if needed)
# Since we're using Nginx as the reverse proxy and PHP-FPM, Apache is not required.
# If Apache is needed for specific purposes, uncomment the following section.

# echo "Creating Apache configuration..."
# cat > apache-config.conf <<EOL
# <VirtualHost *:80>
#     ServerAdmin admin@yourdomain.com
#     DocumentRoot /var/www/html/public

#     <Directory /var/www/html/public>
#         Options Indexes FollowSymLinks
#         AllowOverride All
#         Require all granted
#     </Directory>

#     ErrorLog \${APACHE_LOG_DIR}/error.log
#     CustomLog \${APACHE_LOG_DIR}/access.log combined
# </VirtualHost>
# EOL
# echo "Apache configuration created."

# 8. Create php.ini
echo "Creating php.ini..."

cat > php.ini <<EOL
memory_limit = 256M
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 300
EOL

echo "php.ini created."

# 9. Generate Self-Signed SSL Certificates
echo "Generating self-signed SSL certificates..."

# Check if certificates already exist
if [ ! -f certs/fullchain.pem ] || [ ! -f certs/privkey.pem ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout certs/privkey.pem \
        -out certs/fullchain.pem \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=$STATIC_IP"
    echo "Self-signed SSL certificates generated."
else
    echo "SSL certificates already exist. Skipping generation."
fi

# 10. Set Permissions
echo "Setting file permissions..."

sudo chown -R $USER:$USER src
sudo chmod -R 755 src

echo "Permissions set."

# 11. Build and Start Docker Containers
echo "Building and starting Docker containers..."

docker-compose up --build -d

echo "Docker containers are up and running."

# 12. Generate Laravel APP_KEY
echo "Generating Laravel APP_KEY..."

# Generate the key and capture it
APP_KEY=$(docker-compose exec app php artisan key:generate --show | awk '{print $NF}')

# Update .env with the generated APP_KEY
sed -i "s/^APP_KEY=.*/APP_KEY=$APP_KEY/" .env

# Set the APP_KEY inside the container
docker-compose exec app bash -c "echo 'APP_KEY=$APP_KEY' >> .env"

echo "Laravel APP_KEY generated and updated in .env."

# 13. Run Laravel Artisan Commands
echo "Running Laravel Artisan commands..."

docker-compose exec app php artisan migrate --force
docker-compose exec app php artisan config:cache
docker-compose exec app php artisan route:cache
docker-compose exec app php artisan view:cache

echo "Laravel Artisan commands executed."

# 14. Final Instructions
echo "=== Deployment Completed ==="
echo "You can access your BookStack application at: $APP_URL"
echo "phpMyAdmin is available at: http://$STATIC_IP:8080"
echo "Default Admin Credentials (change immediately):"
echo "Email: admin@admin.com"
echo "Password: password"

echo "To change the admin credentials, access the phpMyAdmin interface or run Laravel commands within the container."

echo "Note: Since SSL is set up with a self-signed certificate, your browser may show a security warning. You can proceed by accepting the risk or set up a proper domain and SSL certificate when available."
