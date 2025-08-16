#!/bin/bash

# === Config ===
NEW_USER="${NEW_USER:-newuser}"
NEW_USER_PASSWORD="${NEW_USER_PASSWORD:-changeme}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-mysqlrootpass}"
CREATE_DATABASE="${CREATE_DATABASE:-false}"
DATABASE_NAME="${DATABASE_NAME:-mydatabase}"
DOMAIN_NAME="${DOMAIN_NAME:-example.com}"
FLASK_APP_NAME="app"
SRC_DIR="/home/$NEW_USER/src"
VENV_DIR="/home/$NEW_USER/venv"
APP_SERVICE_FILE="/etc/systemd/system/${FLASK_APP_NAME}.service"
NGINX_CONF="/etc/nginx/sites-available/${FLASK_APP_NAME}.conf"
SOCK_PATH="${SRC_DIR}/${FLASK_APP_NAME}.sock"
LOG_FILE="/tmp/setup-$(date +%F-%T).log"

# === Logging ===
exec > >(tee -a "$LOG_FILE") 2>&1
echo "🚀 Starting setup for user '$NEW_USER' with domain '$DOMAIN_NAME'..."
echo "📝 Logging setup to $LOG_FILE"

# === Validation ===
if [[ "$NEW_USER_PASSWORD" == "changeme" || "$MYSQL_ROOT_PASSWORD" == "mysqlrootpass" ]]; then
  echo "Error: Please set secure NEW_USER_PASSWORD and MYSQL_ROOT_PASSWORD"
  exit 1
fi

# === System Check ===
if [[ ! -f /etc/debian_version ]]; then
  echo "Error: This script is designed for Debian/Ubuntu systems"
  exit 1
fi

# === System Update ===
sudo apt update && sudo apt upgrade -y || { echo "Failed to update system"; exit 1; }

# === MySQL Setup ===
sudo apt install -y mysql-server || { echo "Failed to install MySQL"; exit 1; }
sudo systemctl is-active --quiet mysql || { echo "MySQL service not running"; exit 1; }

# Secure MySQL credentials
sudo tee /root/.my.cnf > /dev/null <<EOL
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOL
sudo chmod 600 /root/.my.cnf

# Configure MySQL root user
sudo mysql <<EOF || { echo "Failed to configure MySQL root user"; exit 1; }
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

# Secure MySQL installation
sudo mysql_secure_installation <<EOF || { echo "Failed to secure MySQL"; exit 1; }
n
y
y
y
y
EOF

# Create database and user if requested
if [[ "$CREATE_DATABASE" == "true" ]]; then
  sudo mysql <<EOF || { echo "Failed to create database or user"; exit 1; }
CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};
CREATE USER IF NOT EXISTS '${NEW_USER}'@'localhost' IDENTIFIED BY '${NEW_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO '${NEW_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
  echo "✅ MySQL database '$DATABASE_NAME' created and user '$NEW_USER' configured."
fi

# === User Setup ===
sudo adduser --disabled-password --gecos "" $NEW_USER || { echo "Failed to create user"; exit 1; }
echo "${NEW_USER}:${NEW_USER_PASSWORD}" | sudo chpasswd || { echo "Failed to set user password"; exit 1; }
sudo usermod -aG sudo,www-data $NEW_USER

# === Install Dependencies ===
sudo apt install -y python3-pip python3-venv nginx || { echo "Failed to install dependencies"; exit 1; }

# === Flask Setup ===
sudo -u $NEW_USER bash <<EOF || { echo "Failed to set up Flask environment"; exit 1; }
cd /home/$NEW_USER
python3 -m venv venv
source venv/bin/activate
pip install flask gunicorn
mkdir -p src/jobs logs
cd src

cat > app.py <<EOL
from flask import Flask
import os

app = Flask(__name__)

@app.route("/")
def index():
    return "Hello, world"

if __name__ == "__main__":
    app.run(debug=os.getenv("FLASK_ENV") == "development", host="0.0.0.0", port=5000)
EOL

cat > wsgi.py <<EOL
from app import app

if __name__ == "__main__":
    app.run()
EOL

cat > gunicorn_config.py <<EOL
import multiprocessing

workers = multiprocessing.cpu_count() * 2 + 1
bind = 'unix:${SOCK_PATH}'
umask = 0o007
reload = True
accesslog = '/home/$NEW_USER/logs/access.log'
errorlog = '/home/$NEW_USER/logs/error.log'
loglevel = 'info'
EOL
EOF

# === Systemd Service ===
sudo tee $APP_SERVICE_FILE > /dev/null <<EOL
[Unit]
Description=Gunicorn instance to serve Flask application
After=network.target

[Service]
User=$NEW_USER
Group=www-data
WorkingDirectory=${SRC_DIR}
Environment="PATH=${VENV_DIR}/bin"
ExecStart=${VENV_DIR}/bin/gunicorn --config gunicorn_config.py wsgi:app
Restart=always
RestartSec=3
LimitNOFILE=1024

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl start ${FLASK_APP_NAME}.service || { echo "Failed to start Gunicorn service"; exit 1; }
sudo systemctl enable ${FLASK_APP_NAME}.service

# === Nginx Setup ===
sudo tee $NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    location / {
        include proxy_params;
        proxy_pass http://unix:${SOCK_PATH};
    }
}
EOL

sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/ || { echo "Failed to enable Nginx site"; exit 1; }
[ -f /etc/nginx/sites-enabled/default ] && sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx || { echo "Nginx configuration failed"; exit 1; }

# === Firewall ===
sudo ufw status | grep -q "inactive" || echo "⚠️ UFW is already active. Review existing rules."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable || { echo "Failed to configure firewall"; exit 1; }

# === Permissions ===
sudo chmod 750 /home/$NEW_USER
sudo chown $NEW_USER:www-data /home/$NEW_USER -R

# === Validation ===
if curl -s http://$DOMAIN_NAME | grep -q "Hello, world"; then
  echo "✅ Flask app is running and accessible"
else
  echo "❌ Failed to access Flask app"
  exit 1
fi

echo "✅ Setup complete for user: $NEW_USER | domain: $DOMAIN_NAME"
echo "ℹ️ Setup log saved to $LOG_FILE"
echo "ℹ️ Consider setting up SSL: sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME"
