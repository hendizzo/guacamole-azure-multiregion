# Setting Up Let's Encrypt SSL for Guacamole

## Prerequisites

1. **Domain Name**: You must have a domain name that points to your server's public IP
   - Example: guacamole.yourdomain.com → 20.26.236.70
   
2. **Port Forwarding**: Ensure ports 80 and 443 are accessible from the internet
   - Port 80: Required for Let's Encrypt HTTP-01 challenge
   - Port 443: HTTPS traffic

3. **DNS Propagation**: Wait for DNS changes to propagate (can take up to 48 hours)

## Setup Steps

### 1. Update Configuration Files

Edit the following files with your actual domain name:

**File: `docker-compose.yml`**
```yaml
environment:
  CERTBOT_EMAIL: your-actual-email@example.com  # Your real email address
```

**File: `nginx/user_conf.d/guacamole.conf`**
```nginx
server_name         your-domain.com;  # Your actual domain (line 4)
ssl_certificate     /etc/letsencrypt/live/your-domain.com/fullchain.pem;  # Line 7
ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;  # Line 8
ssl_trusted_certificate /etc/letsencrypt/live/your-domain.com/chain.pem;  # Line 9
```

Replace `your-domain.com` with your actual domain in all 4 locations.

### 2. Testing with Staging (Recommended First Time)

Let's Encrypt has rate limits (5 certificates per domain per week). Test first with staging:

**Uncomment this line in `docker-compose.yml`:**
```yaml
# STAGING: 1  # Uncomment for testing
```

### 3. Stop Current Containers

```bash
sudo docker compose down
```

### 4. Start with New Configuration

```bash
sudo docker compose up -d
```

### 5. Monitor the Certificate Request

```bash
sudo docker logs -f nginx_guacamole_compose
```

Watch for:
- "Requesting initial certificate"
- "Successfully received certificate"

This may take a few minutes on first run as it generates Diffie-Hellman parameters.

### 6. Verify SSL is Working

Once the logs show success:
- Visit: https://your-domain.com
- You should see the Guacamole login page with a valid SSL certificate
- If using staging, you'll see a warning (expected - staging certs aren't trusted)

### 7. Switch to Production Certificates

If staging worked:

1. **Edit `docker-compose.yml`**: Comment out or remove `STAGING: 1`
2. **Remove staging certificates**:
   ```bash
   sudo rm -rf ./nginx_secrets/*
   ```
3. **Restart**:
   ```bash
   sudo docker compose down
   sudo docker compose up -d
   ```

### 8. Automatic Renewal

The container automatically checks for certificate renewal every 8 days and renews certificates when they have less than 30 days remaining. No manual intervention needed!

## Troubleshooting

### Certificate Request Failed

**Check DNS:**
```bash
nslookup your-domain.com
dig your-domain.com
```

**Verify Port 80 is accessible:**
```bash
curl -I http://your-domain.com/.well-known/acme-challenge/test
```

**Check logs:**
```bash
sudo docker logs nginx_guacamole_compose
```

### Rate Limit Hit

If you hit Let's Encrypt rate limits:
- Wait 7 days, or
- Use a different domain/subdomain, or
- Use staging for testing

### Domain Not Resolving

- Verify DNS A record points to your server's PUBLIC IP
- Check if you're behind NAT - ensure port forwarding is configured
- Wait for DNS propagation (up to 48 hours)

## Rollback to Self-Signed Certificates

If you need to go back to the old setup:

1. Restore the old nginx configuration in `docker-compose.yml`
2. Run:
   ```bash
   sudo docker compose down
   sudo docker compose up -d
   ```

## Additional Resources

- [docker-nginx-certbot Documentation](https://github.com/JonasAlfredsson/docker-nginx-certbot)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Certbot Documentation](https://certbot.eff.org/docs/)
