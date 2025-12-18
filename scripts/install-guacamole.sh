#!/bin/bash
# Guacamole Docker Installation Script
# This script sets up Apache Guacamole with Docker Compose and Let's Encrypt SSL
# Uses repository: https://github.com/hendizzo/guacamole-azure-multiregion.git

set -e

# Configuration
DOMAIN="${1:-paw.example.com}"
EMAIL="${2:-your-email@example.com}"
REPO_URL="https://github.com/hendizzo/guacamole-azure-multiregion.git"

echo "=========================================="
echo "Guacamole Installation Script"
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "=========================================="

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install Git
echo "Installing Git..."
sudo apt-get install -y git

# Install Docker
echo "Installing Docker..."
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
sudo usermod -aG docker $USER

# Clone the repository
echo "Cloning Guacamole repository..."
cd ~
if [ -d "guacamole-azure-multiregion" ]; then
    echo "Repository already exists, updating..."
    cd guacamole-azure-multiregion
    git pull
else
    git clone ${REPO_URL}
    cd guacamole-azure-multiregion
fi

# Run the prepare script
echo "Running prepare script..."
chmod +x prepare.sh
./prepare.sh

# Create .env file with domain
echo "Configuring domain..."
echo "DOMAIN=${DOMAIN}" > .env

# Update domain in nginx template if needed
if [ -f "nginx/templates/guacamole.conf.template" ]; then
    echo "Domain will be configured via environment variable"
fi

# Start services (without nginx first for certbot challenge)
echo "Starting Guacamole services..."
docker compose up -d guacd postgres guacamole nginx

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 10

# Get SSL certificate
echo "Obtaining SSL certificate..."
docker compose run --rm certbot certonly --webroot \
    --webroot-path=/var/www/certbot \
    --email ${EMAIL} \
    --agree-tos \
    --no-eff-email \
    -d ${DOMAIN}

# Restart nginx to load certificates
echo "Restarting nginx with SSL..."
docker compose restart nginx

# Start certbot renewal service
docker compose up -d certbot

# Get the PostgreSQL password from prepare script output
POSTGRES_PASSWORD=$(grep POSTGRES_PASSWORD .env 2>/dev/null | cut -d'=' -f2)

echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo "Guacamole URL: https://${DOMAIN}/guacamole/"
echo "Default credentials:"
echo "  Username: guacadmin"
echo "  Password: guacadmin"
echo ""
echo "IMPORTANT: Change the default password immediately!"
if [ ! -z "$POSTGRES_PASSWORD" ]; then
    echo "PostgreSQL Password: ${POSTGRES_PASSWORD}"
fi
echo "=========================================="
