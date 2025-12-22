#!/bin/bash
set -e

# Parameters passed from Custom Script Extension
DOMAIN=$1
CERTBOT_EMAIL=$2

echo "=========================================="
echo "Guacamole Installation Script"
echo "=========================================="
echo "Domain: $DOMAIN"
echo "Email: $CERTBOT_EMAIL"
echo ""

# Update system
echo "Updating system packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    nginx \
    certbot \
    python3-certbot-nginx

# Install Docker
echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Clone Guacamole repository
echo "Cloning Guacamole repository..."
cd /home/pawadmin
if [ -d "guacamole-azure-multiregion" ]; then
    rm -rf guacamole-azure-multiregion
fi
git clone https://github.com/hendizzo/guacamole-azure-multiregion.git
cd guacamole-azure-multiregion

# Create .env file
echo "Creating environment configuration..."
cat > .env <<EOF
POSTGRES_USER=guacamole_user
POSTGRES_PASSWORD=$(openssl rand -base64 32)
POSTGRES_DB=guacamole_db
GUACAMOLE_HOME=/etc/guacamole
DOMAIN=$DOMAIN
CERTBOT_EMAIL=$CERTBOT_EMAIL
EOF

# Update docker-compose.yml with domain and email
echo "Configuring Docker Compose..."
sed -i "s/your-domain.com/${DOMAIN}/" docker-compose.yml
sed -i "s/your-email@example.com/${CERTBOT_EMAIL}/" docker-compose.yml

# Initialize database
echo "Initializing Guacamole database..."
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgresql > initdb.sql

# Start services
echo "Starting Guacamole services..."
docker compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Check if Guacamole is responding
echo "Checking Guacamole status..."
for i in {1..30}; do
    if curl -s http://localhost:8080/guacamole/ | grep -q "Guacamole"; then
        echo "✓ Guacamole is running"
        break
    fi
    echo "Waiting for Guacamole to start... ($i/30)"
    sleep 10
done

# Configure Nginx
echo "Configuring Nginx..."
cat > /etc/nginx/sites-available/guacamole <<'NGINX_EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;
    
    # SSL certificates will be added by certbot
    
    location /guacamole/ {
        proxy_pass http://localhost:8080/guacamole/;
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

sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" /etc/nginx/sites-available/guacamole

# Enable site
ln -sf /etc/nginx/sites-available/guacamole /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Restart Nginx
systemctl restart nginx

# Obtain SSL certificate
echo "Obtaining SSL certificate from Let's Encrypt..."
certbot --nginx \
    -d $DOMAIN \
    --non-interactive \
    --agree-tos \
    --email $CERTBOT_EMAIL \
    --redirect

# Setup automatic renewal
echo "Setting up automatic certificate renewal..."
systemctl enable certbot.timer
systemctl start certbot.timer

# Set correct permissions
chown -R pawadmin:pawadmin /home/pawadmin/guacamole-azure-multiregion

echo ""
echo "=========================================="
echo "✓ Installation Complete!"
echo "=========================================="
echo "Guacamole is now accessible at:"
echo "  https://$DOMAIN/guacamole/"
echo ""
echo "Default credentials:"
echo "  Username: guacadmin"
echo "  Password: guacadmin"
echo "  ⚠ CHANGE PASSWORD IMMEDIATELY!"
echo "=========================================="
