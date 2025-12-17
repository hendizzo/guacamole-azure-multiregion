#!/bin/bash
# Guacamole Docker Installation Script
# This script sets up Apache Guacamole with Docker Compose and Let's Encrypt SSL

set -e

# Configuration
DOMAIN="${1:-paw.vorlichmedia.com}"
EMAIL="${2:-your-email@example.com}"

echo "=========================================="
echo "Guacamole Installation Script"
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "=========================================="

# Update system
echo "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

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

# Create guacamole directory
echo "Setting up Guacamole..."
mkdir -p ~/guacamole-docker-compose
cd ~/guacamole-docker-compose

# Clone the repository (or use local files)
if [ ! -f "docker-compose.yml" ]; then
    echo "Creating docker-compose.yml..."
    cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

networks:
  guacamole_network:
    driver: bridge

services:
  guacd:
    container_name: guacd
    image: guacamole/guacd:latest
    restart: always
    networks:
      - guacamole_network

  postgres:
    container_name: postgres_guacamole
    image: postgres:15
    restart: always
    environment:
      POSTGRES_DB: guacamole_db
      POSTGRES_USER: guacamole_user
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./init:/docker-entrypoint-initdb.d:ro
      - postgres_data:/var/lib/postgresql/data
    networks:
      - guacamole_network

  guacamole:
    container_name: guacamole
    image: guacamole/guacamole:latest
    restart: always
    depends_on:
      - guacd
      - postgres
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRES_HOSTNAME: postgres
      POSTGRES_DATABASE: guacamole_db
      POSTGRES_USER: guacamole_user
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    networks:
      - guacamole_network

  nginx:
    container_name: nginx
    image: nginx:latest
    restart: always
    depends_on:
      - guacamole
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/templates:/etc/nginx/templates:ro
      - ./nginx/user_conf.d:/etc/nginx/user_conf.d:ro
      - certbot_etc:/etc/letsencrypt
      - certbot_var:/var/lib/letsencrypt
      - certbot_www:/var/www/certbot
    environment:
      - DOMAIN=${DOMAIN}
    networks:
      - guacamole_network

  certbot:
    container_name: certbot
    image: certbot/certbot:latest
    volumes:
      - certbot_etc:/etc/letsencrypt
      - certbot_var:/var/lib/letsencrypt
      - certbot_www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

volumes:
  postgres_data:
  certbot_etc:
  certbot_var:
  certbot_www:
COMPOSE_EOF
fi

# Create .env file
echo "Creating .env file..."
POSTGRES_PASSWORD=$(openssl rand -base64 32)
cat > .env << ENV_EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DOMAIN=${DOMAIN}
ENV_EOF

echo "Generated PostgreSQL password: ${POSTGRES_PASSWORD}"
echo "Please save this password securely!"

# Initialize database
echo "Setting up database initialization..."
mkdir -p init
cd init
docker run --rm guacamole/guacamole:latest /opt/guacamole/bin/initdb.sh --postgresql > initdb.sql
cd ..

# Create nginx configuration directories
mkdir -p nginx/templates nginx/user_conf.d

# Create nginx template
echo "Creating nginx configuration..."
cat > nginx/templates/guacamole.conf.template << 'NGINX_EOF'
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    client_max_body_size 100M;
    
    location / {
        return 302 /guacamole/;
    }
    
    location /guacamole/ {
        proxy_pass http://guacamole:8080;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_cookie_path /guacamole/ /;
        access_log off;
    }
}
NGINX_EOF

# Run docker compose
echo "Starting Guacamole services..."
newgrp docker << DOCKER_COMMANDS
docker compose up -d guacd postgres guacamole nginx
DOCKER_COMMANDS

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

echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo "Guacamole URL: https://${DOMAIN}/guacamole/"
echo "Default credentials:"
echo "  Username: guacadmin"
echo "  Password: guacadmin"
echo ""
echo "IMPORTANT: Change the default password immediately!"
echo "PostgreSQL Password: ${POSTGRES_PASSWORD}"
echo "=========================================="
