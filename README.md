# 🚀 Guacamole Docker Compose with Let's Encrypt SSL

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://www.docker.com/)
[![Guacamole](https://img.shields.io/badge/guacamole-1.6.0-green.svg)](https://guacamole.apache.org/)

Deploy a **secure, production-ready remote desktop gateway** in minutes. This Docker Compose setup provides **Apache Guacamole** with automatic **SSL/TLS certificate management** via **Let's Encrypt** and certbot. Access Windows (RDP), Linux (SSH), and VNC desktops from any web browser without plugins or client software.

Perfect for IT administrators, developers, system administrators, and organizations needing secure remote access solutions with enterprise features like **session recording**, **file transfer**, **multi-factor authentication (MFA)**, and granular user permissions. Free, open-source, and production-ready.

## 🎯 Why This Solution?

**For IT Professionals & System Administrators:**
- 🔒 **Enterprise Security**: Automatic SSL/TLS certificates from Let's Encrypt with 90-day auto-renewal
- 🌐 **Universal Access**: HTML5-based - works on Windows, Mac, Linux, tablets, and smartphones
- 📹 **Compliance**: Built-in session recording for audit trails and compliance requirements
- 🔐 **Multi-Factor Authentication**: TOTP/2FA support for enhanced security
- 👥 **Multi-User**: Centralized user management with role-based access control

**For Developers & DevOps:**
- 🐳 **Container-Ready**: Full Docker Compose stack - deploy anywhere in seconds
- �� **All-in-One**: Includes nginx reverse proxy, PostgreSQL database, and guacd daemon
- 🔄 **GitOps Compatible**: Infrastructure as code with version control
- 📊 **Monitoring**: Easy integration with logging and monitoring solutions
- 🚀 **Scalable**: Horizontal scaling ready for high-availability deployments

## 🎯 About Apache Guacamole

Apache Guacamole is a clientless remote desktop gateway supporting standard protocols like **VNC**, **RDP**, **SSH**, and **Telnet**. Access your desktops from anywhere using just a web browser - no plugins or client software required.

**Key Benefits:**
- 🌐 **Browser-based (HTML5)** - Works on any device with a web browser
- 🔒 **Secure connections** through SSL/TLS encryption
- 📱 **Mobile-friendly** responsive interface
- 🎥 **Session recording** capabilities for compliance and training
- 👥 **Multi-user support** with granular permissions
- 🔐 **MFA/2FA support** via TOTP authenticators
- 📁 **File transfer** - Upload/download files through the browser
- 🖥️ **Multiple protocols** - RDP, SSH, VNC, Telnet in one platform

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
- ✅ **MFA Support** - Two-factor authentication ready
- ✅ **Comprehensive Documentation** - Setup guides and troubleshooting

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
git clone https://github.com/hendizzo/guacamole-letsencrypt-docker.git
cd guacamole-letsencrypt-docker
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

**How it works:**
- Let's Encrypt certificates are valid for **90 days**
- Auto-renewal triggers when **30 days** remain
- nginx-certbot container checks every **8 days**
- Nginx automatically reloads after successful renewal

**Verify certificate expiration:**
```bash
# Check when your certificate expires
docker exec nginx_guacamole_compose openssl x509 \
  -in /etc/letsencrypt/live/your-domain.com/cert.pem \
  -noout -enddate

# Alternative: View full certificate details
docker exec nginx_guacamole_compose certbot certificates
```

**Check renewal logs:**
```bash
# View certbot renewal activity
docker logs nginx_guacamole_compose | grep -i renew

# View full container logs
docker logs nginx_guacamole_compose
```

**Test renewal process (dry-run):**
```bash
# Safe test - doesn't actually renew
docker exec nginx_guacamole_compose certbot renew --dry-run
```

**Manual renewal (if needed):**
```bash
# Force renewal
docker exec nginx_guacamole_compose certbot renew

# Reload nginx to use new certificate
docker kill --signal=HUP nginx_guacamole_compose
```

**Troubleshooting renewal failures:**

If renewal fails, check:
1. **Ports 80 and 443 are accessible** from the internet
2. **DNS is correctly configured** and propagated
3. **Docker container is running**: `docker ps | grep nginx`
4. **Disk space is available**: `df -h`
5. **Check error logs**: `docker logs nginx_guacamole_compose`

Common issues:
- Firewall blocking ports 80/443
- DNS changes not yet propagated
- Rate limiting (5 failures per hour per domain)
- Container crashed or stopped


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

docker compose stop guacamole postgres
docker compose start postgres
sleep 5
docker exec postgres_guacamole_compose pg_dump -U guacamole_user guacamole_db > "$BACKUP_DIR/database.sql"

tar -czf "$BACKUP_DIR/data.tar.gz" ./data/
tar -czf "$BACKUP_DIR/recordings.tar.gz" ./record/
cp docker-compose.yml "$BACKUP_DIR/"

docker compose up -d
echo "Backup completed: $BACKUP_DIR"
```

## 🔧 Troubleshooting

### Certificate Request Failed

**Solution:**
1. Verify ports 80 and 443 are open
2. Check DNS with `nslookup your-domain.com`
3. Test port accessibility: `curl http://your-domain.com`

### Browser Shows "Not Secure"

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

## 🎓 Use Cases

### IT Help Desk & Remote Support
- Provide secure remote assistance to employees
- No software installation required on end-user devices
- Session recording for training and quality assurance
- Access from any device, anywhere

### Development & Testing
- Access development servers and VMs remotely
- Test applications in different environments
- Share development environments with team members
- SSH access to Linux servers from any device

### Server Administration
- Manage multiple servers from one web interface
- Secure access without exposing SSH/RDP ports
- Multi-factor authentication for critical systems
- Centralized access control and audit logs

### Education & Training
- Provide students access to lab computers
- Record sessions for tutorials
- Browser-based access - works on Chromebooks
- No software installation required

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

## 🔍 Keywords

Remote Desktop Gateway, Apache Guacamole, Let's Encrypt, SSL Certificate, Docker Compose, RDP, SSH, VNC, Telnet, Browser-based Remote Access, Clientless Remote Desktop, HTML5 Remote Desktop, Secure Remote Access, Session Recording, Multi-Factor Authentication, nginx Reverse Proxy, PostgreSQL, ACME Protocol, Certbot, Free SSL, Automatic Certificate Renewal, IT Remote Support, Remote Server Management, Cloud Remote Desktop, Self-hosted Remote Access

---

**Made with ❤️ for the open-source community**
