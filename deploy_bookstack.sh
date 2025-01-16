# !/bin/bash

# deploy_bookstack.sh
# A script to automate the deployment of BookStack on Ubuntu 24.04 without Docker.

set -e

# ===========================
# Function Definitions
# ===========================

# Function to prompt for input with a default value
prompt() {
    local PROMPT_MESSAGE=$1
    local DEFAULT_VALUE=$2
    read -p "$PROMPT_MESSAGE [$DEFAULT_VALUE]: " INPUT
    echo "${INPUT:-$DEFAULT_VALUE}"
}

# Function to log messages
log() {
    echo "$1"
    echo "$1" >> "$LOGPATH"
}

# Function to handle errors
error_out() {
    echo "ERROR: $1" | tee -a "$LOGPATH" 1>&2
    exit 1
}

# ===========================
# Initial Setup
# ===========================

echo "=== BookStack Deployment Script ==="

# Generate a path for a log file to output into for debugging
LOGPATH=$(realpath "bookstack_install_$(date +%s).log")
touch "$LOGPATH"

# Get the current user running the script
SCRIPT_USER="${SUDO_USER:-$USER}"

# Get the current machine IP address
CURRENT_IP=$(hostname -I | awk '{print $1}')

# Set DEBIAN_FRONTEND to noninteractive to prevent prompts
export DEBIAN_FRONTEND=noninteractive

# ===========================
# Step 1: System Updates and Dependencies
# ===========================

log "Updating system packages..."
apt update && apt upgrade -y >> "$LOGPATH" 2>&1

log "Installing required system packages..."
apt install -y git unzip apache2 curl mysql-server-8.0 \
php8.3 php8.3-fpm php8.3-curl php8.3-mbstring php8.3-ldap \
php8.3-xml php8.3-zip php8.3-gd php8.3-mysql >> "$LOGPATH" 2>&1

# ===========================
# Step 2: Database Setup
# ===========================

log "Starting MySQL service..."
systemctl start mysql.service
systemctl enable mysql.service

# Secure MySQL installation (optional but recommended)
# You can uncomment and customize the following lines if you want to secure MySQL
# log "Securing MySQL installation..."
# mysql_secure_installation >> "$LOGPATH" 2>&1

# Prompt for MySQL Root Password if you have set one, else assume no password
read -s -p "Enter MySQL root password (leave blank if none): " MYSQL_ROOT_PASSWORD
echo

# Generate a password for the BookStack database user if not provided
MYSQL_PASSWORD=$(prompt "Enter MySQL password for BookStack user" "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)")

# Create BookStack database and user
log "Setting up MySQL database for BookStack..."
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE bookstack;
CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON bookstack.* TO 'bookstack'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
else
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SCRIPT
CREATE DATABASE bookstack;
CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON bookstack.* TO 'bookstack'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
fi

# ===========================
# Step 3: Clone BookStack Repository
# ===========================

# Directory to install BookStack
BOOKSTACK_DIR="/var/www/bookstack"

# Prompt for your custom BookStack repository URL
CUSTOM_REPO_URL=$(prompt "Enter your custom BookStack repository URL" "https://github.com/YourUsername/BookStack.git")

log "Cloning BookStack repository from $CUSTOM_REPO_URL..."
git clone "$CUSTOM_REPO_URL" "$BOOKSTACK_DIR" >> "$LOGPATH" 2>&1

# Navigate to BookStack directory
cd "$BOOKSTACK_DIR"

# Checkout the desired branch or commit if necessary
# For example, to checkout the main branch:
git checkout main >> "$LOGPATH" 2>&1

# ===========================
# Step 4: Install Composer and PHP Dependencies
# ===========================

log "Installing Composer..."
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    error_out "Invalid Composer installer checksum"
fi

php composer-setup.php --quiet >> "$LOGPATH" 2>&1
rm composer-setup.php
mv composer.phar /usr/local/bin/composer

log "Installing PHP dependencies with Composer..."
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader >> "$LOGPATH" 2>&1

# ===========================
# Step 5: Configure Environment Variables
# ===========================

# Prompt for the domain or use IP
DOMAIN=$(prompt "Enter your domain (or leave blank to use server IP)" "")

if [ -z "$DOMAIN" ]; then
    DOMAIN="$CURRENT_IP"
fi

APP_URL="http://$DOMAIN"

# Prompt for additional environment variables if needed
# For example, you can prompt for mail settings here

log "Configuring environment variables..."
cp .env.example .env
sed -i "s@APP_URL=.*@APP_URL=$APP_URL@" .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=bookstack/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=bookstack/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$MYSQL_PASSWORD/" .env

# Generate the application key
log "Generating Laravel APP_KEY..."
php artisan key:generate --no-interaction --force >> "$LOGPATH" 2>&1

# ===========================
# Step 6: Configure Apache
# ===========================

log "Configuring Apache for BookStack..."

# Enable necessary Apache modules
a2enmod rewrite proxy_fcgi setenvif >> "$LOGPATH" 2>&1
a2enconf php8.3-fpm >> "$LOGPATH" 2>&1

# Create Apache Virtual Host for BookStack
cat > /etc/apache2/sites-available/bookstack.conf <<EOL
<VirtualHost *:80>
    ServerName $DOMAIN

    ServerAdmin webmaster@localhost
    DocumentRoot $BOOKSTACK_DIR/public

    <Directory $BOOKSTACK_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        <IfModule mod_rewrite.c>
            RewriteEngine On

            # Handle Authorization Header
            RewriteCond %{HTTP:Authorization} .
            RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

            # Redirect Trailing Slashes If Not A Folder...
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_URI} (.+)/$
            RewriteRule ^ %1 [L,R=301]

            # Handle Front Controller...
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteRule ^ index.php [L]
        </IfModule>
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/bookstack_error.log
    CustomLog \${APACHE_LOG_DIR}/bookstack_access.log combined
</VirtualHost>
EOL

# Disable the default site and enable the BookStack site
a2dissite 000-default.conf >> "$LOGPATH" 2>&1
a2ensite bookstack.conf >> "$LOGPATH" 2>&1

# Test Apache configuration and reload
apache2ctl configtest >> "$LOGPATH" 2>&1
systemctl reload apache2 >> "$LOGPATH" 2>&1

# ===========================
# Step 7: Finalize Installation
# ===========================

log "Running Laravel Artisan commands..."
php artisan migrate --no-interaction --force >> "$LOGPATH" 2>&1
php artisan config:cache >> "$LOGPATH" 2>&1
php artisan route:cache >> "$LOGPATH" 2>&1
php artisan view:cache >> "$LOGPATH" 2>&1

# ===========================
# Step 8: Set Permissions
# ===========================

log "Setting file and folder permissions..."
chown -R "$SCRIPT_USER":www-data "$BOOKSTACK_DIR"
chmod -R 755 "$BOOKSTACK_DIR"
chmod -R 775 "$BOOKSTACK_DIR/storage" "$BOOKSTACK_DIR/bootstrap/cache" "$BOOKSTACK_DIR/public/uploads"
chmod 740 "$BOOKSTACK_DIR/.env"

# ===========================
# Completion Message
# ===========================

log "=== Deployment Completed ==="
log "You can access your BookStack application at: $APP_URL"
log "Default Admin Credentials (change immediately):"
log "Email: admin@admin.com"
log "Password: password"

log "To change the admin credentials, access the application directly or update the database."

log "BookStack install path: $BOOKSTACK_DIR"
log "Install script log: $LOGPATH"
