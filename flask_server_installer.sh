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

echo "🚀 Starting setup for user '$NEW_USER' with domain '$DOMAIN_NAME'..."

sudo apt update && sudo apt upgrade -y

sudo apt install -y mysql-server
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

if [[ "$CREATE_DATABASE" == "true" ]]; then
  sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};
GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO 'root'@'localhost';
FLUSH PRIVILEGES;
EOF
  echo "✅ MySQL database '$DATABASE_NAME' created."
fi

sudo adduser --disabled-password --gecos "" $NEW_USER
echo "${NEW_USER}:${NEW_USER_PASSWORD}" | sudo chpasswd
sudo usermod -aG sudo $NEW_USER

sudo apt install -y python3-pip python3-venv nginx

sudo -u $NEW_USER bash <<EOF
cd /home/$NEW_USER
python3 -m venv venv
source venv/bin/activate
pip install flask gunicorn
mkdir -p src/jobs
cd src

cat > app.py <<EOL
from flask import Flask

app = Flask(__name__)

@app.route("/")
def index():
    return "Hello, world"

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
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
accesslog = '-'
errorlog = '-'
EOL
EOF

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

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl start ${FLASK_APP_NAME}.service
sudo systemctl enable ${FLASK_APP_NAME}.service

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

sudo ln -s $NGINX_CONF /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx


sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

sudo chmod 775 /home/$NEW_USER


echo "✅ Setup complete for user: $NEW_USER | domain: $DOMAIN_NAME"
