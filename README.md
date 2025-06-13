# Flask Deployer-Auto

A fully automated Bash script to deploy a Flask app with Gunicorn and Nginx on Ubuntu, with optional MySQL setup, system user creation, and custom domain configuration.

## 🚀 Features

- Creates a new Linux user with secure password
- Installs and configures MySQL (optional database setup)
- Sets up Flask app in a Python virtual environment
- Deploys using Gunicorn with a systemd service
- Configures Nginx as a reverse proxy with domain support
- Enables UFW firewall rules for web and SSH access
- Adds optional cron jobs for background tasks

## ⚙️ Configuration

You can either:
1. **Edit variables directly in the script**
2. **Pass values via environment variables when running**

### Supported Variables

| Variable              | Description                                  | Required | Default          |
|-----------------------|----------------------------------------------|----------|------------------|
| `NEW_USER`            | New system username                          | ✅        | `newuser`        |
| `NEW_USER_PASSWORD`   | Password for the new user                    | ✅        | `changeme`       |
| `MYSQL_ROOT_PASSWORD` | Root password for MySQL                      | ✅        | `mysqlrootpass`  |
| `CREATE_DATABASE`     | `true` or `false` to create a MySQL database | ✅        | `false`          |
| `DATABASE_NAME`       | Name of the database (if created)            | ⚠️        | `mydatabase`     |
| `DOMAIN_NAME`         | Domain for Nginx server_name                 | ✅        | `example.com`    |

## 🧪 Example Usage

```bash
NEW_USER=client1 \
NEW_USER_PASSWORD=StrongPass123 \
MYSQL_ROOT_PASSWORD=RootSQLPass! \
CREATE_DATABASE=true \
DATABASE_NAME=client1db \
DOMAIN_NAME=client1.com \
sudo ./flask-deployer.sh
