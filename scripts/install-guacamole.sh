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

# Update docker-compose.yml with email
echo "Configuring Let's Encrypt email..."
sed -i "s/CERTBOT_EMAIL: your-email@example.com/CERTBOT_EMAIL: ${EMAIL}/" docker-compose.yml

# Update nginx configuration with domain
echo "Configuring domain in nginx..."
mkdir -p nginx/user_conf.d
sed -i "s/your-domain\.com/${DOMAIN}/g" nginx/user_conf.d/guacamole.conf

# Start services - nginx-certbot will automatically obtain SSL certificate
echo "Starting Guacamole services..."
echo "The nginx-certbot container will automatically obtain SSL certificate..."
echo "This process takes 2-3 minutes..."
docker compose up -d

# Wait for all services to initialize
echo "Waiting for services to start..."
sleep 30

# Check container status
echo "Checking service status..."
docker compose ps

# Wait for SSL certificate acquisition
echo "Waiting for Let's Encrypt SSL certificate acquisition (up to 2 minutes)..."
for i in {1..24}; do
    if docker compose logs nginx 2>&1 | grep -q "Certificate obtained"; then
        echo "SSL certificate obtained successfully!"
        break
    elif docker compose logs nginx 2>&1 | grep -q "Cert not yet due for renewal"; then
        echo "SSL certificate already exists and is valid!"
        break
    fi
    sleep 5
    echo "Still waiting for SSL certificate... ($((i*5)) seconds)"
done

# Final status check
echo ""
echo "Final service status:"
docker compose ps

# Show nginx logs for troubleshooting
echo ""
echo "Nginx/Certbot logs (last 20 lines):"
docker compose logs --tail=20 nginx

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
