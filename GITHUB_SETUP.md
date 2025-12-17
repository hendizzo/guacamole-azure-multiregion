# GitHub Repository Setup Guide

Follow these steps to create your own GitHub repository from this deployment.

## Prerequisites

- GitHub account
- Git configured on your local machine
- Completed Guacamole deployment

## Step 1: Create a New GitHub Repository

1. Go to https://github.com/new
2. **Repository name**: `guacamole-docker-compose` (or your preferred name)
3. **Description**: "Production-ready Apache Guacamole with Let's Encrypt SSL automation"
4. **Visibility**: Choose Public or Private
5. **DO NOT** initialize with README, .gitignore, or license (we have these already)
6. Click "Create repository"

## Step 2: Disconnect from Original Repository

```bash
cd /opt/guacamole-docker-compose

# Remove the original remote
git remote remove origin

# Verify it's removed
git remote -v
```

## Step 3: Add Your GitHub Repository as Remote

```bash
# Replace 'yourusername' with your GitHub username
git remote add origin https://github.com/yourusername/guacamole-docker-compose.git

# Verify it's added
git remote -v
```

## Step 4: Prepare Files for Commit

### Important: Remove Sensitive Information

Before committing, update docker-compose.yml to use placeholders for sensitive data:

```bash
# Edit docker-compose.yml
nano docker-compose.yml

# Change this:
POSTGRES_PASSWORD: 'River!7-Cloud$9-Hawk@3-Stone#5'
CERTBOT_EMAIL: hendizzo@hotmail.com

# To this:
POSTGRES_PASSWORD: 'ChangeThisToASecurePassword123!'
CERTBOT_EMAIL: your-email@example.com
```

### Clean Up Unnecessary Files

```bash
# Remove old README backup
rm README.md.old

# Remove any local data (don't commit these)
# They're already in .gitignore but let's be sure
rm -rf data/* nginx_secrets/* record/* drive/*
```

## Step 5: Stage Your Changes

```bash
# Add all new and modified files
git add .gitignore
git add README.md
git add CONTRIBUTING.md
git add LETSENCRYPT_SETUP.md
git add .env.example
git add docker-compose.yml
git add nginx/user_conf.d/
git add nginx/templates/guacamole.conf.template

# Check what will be committed
git status
```

## Step 6: Commit Your Changes

```bash
git commit -m "Add Let's Encrypt SSL automation with comprehensive documentation

- Integrated docker-nginx-certbot for automatic SSL certificates
- Added detailed README with setup instructions
- Included troubleshooting guide
- Added contribution guidelines
- Created environment variable template
- Updated nginx configuration for Let's Encrypt
- Added .gitignore for sensitive data"
```

## Step 7: Push to GitHub

### First Time Push

```bash
# Push to main branch (or master, depending on your setup)
git push -u origin master
```

### If you get an error about branch names

```bash
# GitHub now prefers 'main' as default branch name
git branch -M main
git push -u origin main
```

## Step 8: Configure Repository Settings (Optional)

On GitHub:

1. Go to your repository → Settings → General
2. **Features**: Enable Issues, Discussions (optional)
3. **Pull Requests**: Enable "Allow squash merging"
4. Go to Settings → Pages (if you want documentation website)

## Step 9: Add Repository Badges (Optional)

Update README.md with your actual repository:

```markdown
[![GitHub Stars](https://img.shields.io/github/stars/yourusername/guacamole-docker-compose)](https://github.com/yourusername/guacamole-docker-compose/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/yourusername/guacamole-docker-compose)](https://github.com/yourusername/guacamole-docker-compose/issues)
```

## Step 10: Create a Release (Optional)

```bash
# Tag your first release
git tag -a v1.0.0 -m "First release with Let's Encrypt SSL automation"
git push origin v1.0.0
```

Then on GitHub:
1. Go to Releases → Draft a new release
2. Choose the tag v1.0.0
3. Release title: "v1.0.0 - Initial Release"
4. Add release notes describing features

## Future Updates

When you make changes locally:

```bash
# Make your changes
git add .
git commit -m "Descriptive commit message"
git push
```

## Cloning Your Repository (For Others)

Others can now use your repository:

```bash
git clone https://github.com/yourusername/guacamole-docker-compose.git
cd guacamole-docker-compose
./prepare.sh
# ... follow README instructions
```

## Troubleshooting

### Authentication Issues

If you have trouble pushing:

1. **Use Personal Access Token** instead of password:
   - GitHub Settings → Developer settings → Personal access tokens → Generate new token
   - Use token as password when prompted

2. **Or use SSH**:
   ```bash
   # Change remote to SSH
   git remote set-url origin git@github.com:yourusername/guacamole-docker-compose.git
   ```

### Permission Denied

```bash
# If you don't have permission, you may need to fork first
# Then clone your fork and follow the steps above
```

## Security Reminders

✅ **DO commit:**
- Configuration templates
- Documentation
- Scripts
- Example files

❌ **DON'T commit:**
- Actual passwords
- SSL certificates
- Database data
- Session recordings
- Personal email addresses

These are automatically excluded by `.gitignore`.

---

**Congratulations!** Your repository is now on GitHub and ready to be shared with the community! 🎉
