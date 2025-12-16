# 🚀 Guacamole Docker Compose with Let's Encrypt SSL

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://www.docker.com/)
[![Guacamole](https://img.shields.io/badge/guacamole-1.6.0-green.svg)](https://guacamole.apache.org/)

A production-ready Apache Guacamole deployment with automatic Let's Encrypt SSL certificates, PostgreSQL database, and nginx reverse proxy. One-command setup for a fully functional remote desktop gateway.

## 📋 Table of Contents

- [About Apache Guacamole](#about-apache-guacamole)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [SSL Certificate Setup](#ssl-certificate-setup)
- [Security Considerations](#security-considerations)
- [Backup & Restore](#backup--restore)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

## 🎯 About Apache Guacamole

Apache Guacamole is a clientless remote desktop gateway supporting standard protocols like VNC, RDP, SSH, and Telnet. Access your desktops from anywhere using just a web browser - no plugins or client software required.

**Key Benefits:**
- 🌐 Browser-based (HTML5) - works on any device
- 🔒 Secure connections through SSL/TLS
- 📱 Mobile-friendly interface
- 🎥 Session recording capabilities
- 👥 Multi-user support with granular permissions
- 🔐 MFA/2FA support

Learn more at the [official website](https://guacamole.apache.org/).

## ✨ Features

This deployment includes:

- ✅ **Automatic SSL with Let's Encrypt** - Production-ready HTTPS certificates
- ✅ **Auto-renewal** - Certificates renew automatically every 90 days
- ✅ **PostgreSQL Database** - Persistent user and connection storage
- ✅ **Nginx Reverse Proxy** - Efficient request handling and SSL termination
- ✅ **Docker Compose** - Easy deployment and management
- ✅ **Session Recording** - Record and replay remote sessions
- ✅ **File Transfer** - Upload/download files through browser
- ✅ **Connection Sharing** - Multiple users can share sessions

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│  Internet (HTTPS Traffic)                       │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │  nginx-certbot         │
         │  (SSL/TLS Termination) │
         │  Ports: 80, 443        │
         └────────────┬───────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │  Guacamole Web App     │
         │  (Java/Tomcat)         │
         │  Port: 8080            │
         └─────┬────────────┬─────┘
               │            │
       ┌───────▼────┐   ┌──▼────────┐
       │   guacd    │   │ PostgreSQL│
       │  (Proxy)   │   │ (Database)│
       │ Port: 4822 │   │ Port: 5432│
       └────────────┘   └───────────┘
```

## 📦 Prerequisites

### Required

- **Docker Engine** 20.10 or later
- **Docker Compose** 2.0 or later
- **Domain Name** pointing to your server's public IP
- **Ports 80 and 443** accessible from the internet
- **Linux Server** (Ubuntu 20.04+ recommended)

### Optional

- **Email Address** for Let's Encrypt notifications
- **Cloud Provider** (AWS, Azure, GCP, etc.) or VPS

### System Requirements

- **CPU**: 2+ cores recommended
- **RAM**: 4GB minimum, 8GB recommended
- **Disk**: 20GB minimum for OS + 10GB for recordings
- **Network**: Stable internet connection with public IP

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/guacamole-docker-compose.git
cd guacamole-docker-compose
```

### 2. Run Initial Setup

```bash
chmod +x prepare.sh
./prepare.sh
```

This script will:
- Generate database initialization SQL
- Create necessary directories
- Set proper permissions

### 3. Configure Your Domain

Edit `docker-compose.yml`:

```yaml
environment:
  CERTBOT_EMAIL: your-email@example.com  # Change this!
```

Edit `nginx/user_conf.d/guacamole.conf`:

```nginx
server_name         your-domain.com;  # Change this!
ssl_certificate     /etc/letsencrypt/live/your-domain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
ssl_trusted_certificate /etc/letsencrypt/live/your-domain.com/chain.pem;
```

Replace `your-domain.com` in **4 locations** within the file.

### 4. Configure DNS

Ensure your domain's A record points to your server's public IP:

```bash
# Verify DNS is configured
nslookup your-domain.com
```

### 5. Open Firewall Ports

**For Azure:**
- Go to: VM → Networking → Add inbound port rule
- Add rules for ports 80 (HTTP) and 443 (HTTPS)

**For AWS Security Groups:**
```bash
aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 443 --cidr 0.0.0.0/0
```

**For UFW (Ubuntu):**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

### 6. Start the Stack

#### Option A: Test with Staging Certificates First (Recommended)

```bash
# Uncomment STAGING: 1 in docker-compose.yml first
docker compose up -d

# Watch logs to verify success
docker logs -f nginx_guacamole_compose

# Once successful, switch to production:
docker compose down
rm -rf ./nginx_secrets/*
# Comment out STAGING: 1 in docker-compose.yml
docker compose up -d
```

#### Option B: Direct Production Deployment

```bash
docker compose up -d
```

### 7. Access Guacamole

Visit: `https://your-domain.com`

**Default Credentials:**
- Username: `guacadmin`
- Password: `guacadmin`

**⚠️ IMPORTANT:** Change these credentials immediately!

## ⚙️ Configuration

### Change Database Password

**Before first deployment**, update in `docker-compose.yml`:

```yaml
postgres:
  environment:
    POSTGRES_PASSWORD: 'YourSecurePasswordHere'

guacamole:
  environment:
    POSTGRESQL_PASSWORD: 'YourSecurePasswordHere'
```

### Add Remote Connections

1. Log in to Guacamole
2. Go to Settings (top right) → Connections
3. Click "New Connection"
4. Configure:
   - **Name**: Descriptive name
   - **Protocol**: RDP, SSH, VNC, or Telnet
   - **Network**: Hostname and port
   - **Authentication**: Username and password

### Configure Session Recording

Recordings are stored in `./record/` directory.

**Enable recording per connection:**
1. Settings → Connections → Edit Connection
2. Screen Recording section:
   - Recording Path: Use `${HISTORY_PATH}/${HISTORY_UUID}`
   - Create Recording Path: Checked

### User Management

**Create new users:**
1. Settings → Users → New User
2. Set username and password
3. Assign permissions and connections

**Enable MFA:**
1. Settings → Preferences → TOTP
2. Scan QR code with authenticator app

## 🔐 SSL Certificate Setup

This deployment uses [docker-nginx-certbot](https://github.com/JonasAlfredsson/docker-nginx-certbot) for automatic Let's Encrypt SSL certificates.

### Certificate Renewal

Certificates automatically renew when they have less than 30 days remaining. The container checks every 8 days.

**Manual renewal:**
```bash
docker exec nginx_guacamole_compose certbot renew
```

**Force reload nginx:**
```bash
docker kill --signal=HUP nginx_guacamole_compose
```

### Using Staging Certificates (Testing)

To avoid Let's Encrypt rate limits during testing:

```yaml
# In docker-compose.yml
environment:
  STAGING: 1  # Uncomment this line
```

Staging certificates will show a browser warning (expected).

## 🔒 Security Considerations

### Essential Security Steps

1. **Change Default Credentials** immediately after deployment
2. **Change Database Password** in docker-compose.yml before first start
3. **Restrict File Permissions**
   ```bash
   chmod 600 docker-compose.yml
   chmod 700 nginx_secrets/
   ```
4. **Enable MFA** for all admin users
5. **Regular Updates**
   ```bash
   docker compose pull
   docker compose up -d
   ```

### Network Security

- Keep only ports 80 and 443 exposed
- Use strong SSL/TLS ciphers (already configured)
- Enable HSTS headers (already configured)
- Consider IP whitelisting for admin access

## 💾 Backup & Restore

### What to Backup

1. **Database** (`./data/`)
2. **Session recordings** (`./record/`)
3. **docker-compose.yml** (contains passwords)

### Backup Script

```bash
#!/bin/bash
BACKUP_DIR="/backup/guacamole/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Stop containers
docker compose stop guacamole postgres

# Backup database
docker compose start postgres
sleep 5
docker exec postgres_guacamole_compose pg_dump -U guacamole_user guacamole_db > "$BACKUP_DIR/database.sql"

# Backup data directory
tar -czf "$BACKUP_DIR/data.tar.gz" ./data/
tar -czf "$BACKUP_DIR/recordings.tar.gz" ./record/

# Backup configuration
cp docker-compose.yml "$BACKUP_DIR/"

# Restart containers
docker compose up -d

echo "Backup completed: $BACKUP_DIR"
```

## 🔧 Troubleshooting

### Certificate Request Failed

**Error:** "Timeout during connect (likely firewall problem)"

**Solution:**
1. Verify ports 80 and 443 are open
2. Check DNS with `nslookup your-domain.com`
3. Test port accessibility: `curl http://your-domain.com`

### Browser Shows "Not Secure"

**Cause:** Browser cached old staging certificate

**Solution:**
1. Hard refresh: `Ctrl+F5` (Windows) or `Cmd+Shift+R` (Mac)
2. Clear browser cache
3. Try incognito/private mode

### Can't Connect to Remote Desktop

**Check:**
1. Connection settings (hostname, port, protocol)
2. Remote desktop service is running
3. Firewall allows connections from Guacamole server
4. Credentials are correct

**View logs:**
```bash
docker logs guacamole_compose
docker logs guacd_compose
```

### Container Won't Start

```bash
# Check logs for errors
docker logs container_name

# Restart Docker service
sudo systemctl restart docker
docker compose up -d
```

## 🎓 Advanced Usage

### Using Custom SSL Certificates

If you have your own SSL certificates:

1. Comment out Let's Encrypt setup in docker-compose.yml
2. Place certificates in `./nginx/ssl/`
3. Update nginx configuration to use your certificates

### Multi-Factor Authentication (MFA)

1. Install TOTP extension (included by default)
2. Users enable in Settings → Preferences → TOTP

## 📚 Additional Resources

- [Apache Guacamole Documentation](https://guacamole.apache.org/doc/gug/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [nginx-certbot GitHub](https://github.com/JonasAlfredsson/docker-nginx-certbot)

## 📝 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⭐ Acknowledgments

- Based on [boschkundendienst/guacamole-docker-compose](https://github.com/boschkundendienst/guacamole-docker-compose)
- Uses [jonasal/nginx-certbot](https://github.com/JonasAlfredsson/docker-nginx-certbot) for SSL automation
- Built on [Apache Guacamole](https://guacamole.apache.org/)

---

**Made with ❤️ for the open-source community**
