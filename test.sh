#!/bin/bash

# GamePort Installation Script
# This script automates the installation of GamePort on your server

# Text formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print GamePort banner
echo -e "${BLUE}"
echo "  _____                      _____           _   "
echo " / ____|                    |  __ \         | |  "
echo "| |  __  __ _ _ __ ___   ___| |__) |__  _ __| |_ "
echo "| | |_ |/ _\` | '_ \` _ \ / _ \  ___/ _ \| '__| __|"
echo "| |__| | (_| | | | | | |  __/ |  | (_) | |  | |_ "
echo " \_____|\__,_|_| |_| |_|\___|_|   \___/|_|   \__|"
echo -e "${NC}"
echo "Modern Game Server Management Panel"
echo "====================================="

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}Error: This script must be run as root${NC}" 1>&2
   exit 1
fi

echo -e "${GREEN}Starting GamePort installation...${NC}"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    echo -e "Detected OS: ${BLUE}$OS $VERSION${NC}"
else
    echo -e "${RED}Unsupported OS. Please use Ubuntu 20.04+, Debian 11+, or CentOS 8+${NC}"
    exit 1
fi

# Check system requirements
echo "Checking system requirements..."
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
DISK_SPACE=$(df -m / | awk 'NR==2 {print $4}')

echo -e "CPU Cores: ${BLUE}$CPU_CORES${NC}"
echo -e "Total RAM: ${BLUE}$TOTAL_RAM MB${NC}"
echo -e "Free Disk Space: ${BLUE}$DISK_SPACE MB${NC}"

if [ $CPU_CORES -lt 2 ]; then
    echo -e "${RED}Warning: GamePort recommends at least 2 CPU cores${NC}"
fi

if [ $TOTAL_RAM -lt 2048 ]; then
    echo -e "${RED}Warning: GamePort recommends at least 2GB of RAM${NC}"
fi

if [ $DISK_SPACE -lt 10240 ]; then
    echo -e "${RED}Warning: GamePort recommends at least 10GB of free disk space${NC}"
fi

# Install dependencies
echo -e "${GREEN}Installing dependencies...${NC}"

case $OS in
    ubuntu|debian)
        apt update -y
        apt install -y curl wget git nodejs npm docker.io docker-compose mysql-server redis-server
        systemctl enable --now docker
        systemctl enable --now mysql
        systemctl enable --now redis-server
        ;;
    centos|fedora|rhel)
        dnf -y update
        dnf -y install curl wget git nodejs npm docker docker-compose mysql-server redis
        systemctl enable --now docker
        systemctl enable --now mysqld
        systemctl enable --now redis
        ;;
    *)
        echo -e "${RED}Unsupported OS. Please install dependencies manually.${NC}"
        exit 1
        ;;
esac

# Create gameport user and directories
echo -e "${GREEN}Setting up user and directories...${NC}"
id -u gameport &>/dev/null || useradd -r -m -s /bin/bash gameport
usermod -aG docker gameport

# Create directories
mkdir -p /opt/gameport
mkdir -p /var/lib/gameport
mkdir -p /etc/gameport
mkdir -p /var/log/gameport

# Clone repository
echo -e "${GREEN}Cloning GamePort repository...${NC}"
git clone https://github.com/gameport/gameport.git /opt/gameport
cd /opt/gameport
npm install --production

# Generate random secrets
JWT_SECRET=$(openssl rand -hex 32)
APP_KEY=$(openssl rand -hex 32)

# Create database
echo -e "${GREEN}Setting up database...${NC}"
DB_PASSWORD=$(openssl rand -base64 16)

# Create database and user
mysql -e "CREATE DATABASE IF NOT EXISTS gameport;"
mysql -e "CREATE USER IF NOT EXISTS 'gameport'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON gameport.* TO 'gameport'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Create configuration file
echo -e "${GREEN}Creating configuration file...${NC}"
cat > /etc/gameport/config.json <<EOL
{
  "app": {
    "name": "GamePort",
    "url": "http://localhost:3000",
    "port": 3000,
    "environment": "production",
    "secretKey": "$APP_KEY"
  },
  "database": {
    "client": "mysql",
    "connection": {
      "host": "localhost",
      "port": 3306,
      "user": "gameport",
      "password": "$DB_PASSWORD",
      "database": "gameport"
    }
  },
  "redis": {
    "host": "localhost",
    "port": 6379
  },
  "storage": {
    "path": "/var/lib/gameport"
  },
  "docker": {
    "socket": "/var/run/docker.sock"
  },
  "jwt": {
    "secret": "$JWT_SECRET"
  }
}
EOL

# Set permissions
chown -R gameport:gameport /opt/gameport
chown -R gameport:gameport /var/lib/gameport
chown -R gameport:gameport /etc/gameport
chown -R gameport:gameport /var/log/gameport
chmod 600 /etc/gameport/config.json

# Run database migrations
echo -e "${GREEN}Running database migrations...${NC}"
cd /opt/gameport
NODE_ENV=production CONFIG_PATH=/etc/gameport/config.json npm run migrate

# Create systemd service
echo -e "${GREEN}Creating systemd service...${NC}"
cat > /etc/systemd/system/gameport.service <<EOL
[Unit]
Description=GamePort Game Server Management Panel
After=network.target mysql.service redis.service docker.service

[Service]
Type=simple
User=gameport
Group=gameport
WorkingDirectory=/opt/gameport
ExecStart=/usr/bin/node /opt/gameport/index.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=gameport
Environment=NODE_ENV=production
Environment=CONFIG_PATH=/etc/gameport/config.json
Environment=JWT_SECRET=$JWT_SECRET

[Install]
WantedBy=multi-user.target
EOL

# Create CLI tool symlink
ln -sf /opt/gameport/scripts/gameport-cli.js /usr/local/bin/gameport-cli
chmod +x /usr/local/bin/gameport-cli

# Enable and start service
systemctl daemon-reload
systemctl enable gameport
systemctl start gameport

# Installation complete
echo -e "${GREEN}GamePort has been successfully installed!${NC}"
echo ""
echo -e "${BLUE}To create an admin user, run:${NC}"
echo -e "  gameport-cli admin:create --email=admin@example.com --name=\"Admin User\" --password=your_password"
echo ""
echo -e "${BLUE}Access the panel at:${NC} http://$(hostname -I | awk '{print $1}'):3000"
echo ""
echo -e "${BLUE}Configuration file:${NC} /etc/gameport/config.json"
echo -e "${BLUE}Installation directory:${NC} /opt/gameport"
echo -e "${BLUE}Data directory:${NC} /var/lib/gameport"
echo -e "${BLUE}Log directory:${NC} /var/log/gameport"
echo ""
echo -e "${GREEN}Thank you for installing GamePort!${NC}"
