#!/usr/bin/env bash
set -euo pipefail

# Update and install dependencies
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y postfix postfix-mysql dovecot-core dovecot-imapd dovecot-lmtpd dovecot-mysql opendkim opendkim-tools mysql-server python3-venv python3-pip nginx certbot python3-certbot-dns-cloudflare jq

# Create vmail user
id -u vmail &>/dev/null || useradd -r -u 5000 vmail -U -d /var/mail
mkdir -p /var/mail/vhosts/webiime.ir
chown -R vmail:vmail /var/mail

# Configure MySQL for virtual users
mysql -uroot <<'SQL'
CREATE DATABASE IF NOT EXISTS mailserver CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'mailuser'@'localhost' IDENTIFIED BY 'mailpassword';
GRANT SELECT ON mailserver.* TO 'mailuser'@'localhost';
FLUSH PRIVILEGES;
SQL

mysql -uroot mailserver <<'SQL'
CREATE TABLE IF NOT EXISTS virtual_domains (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50) NOT NULL UNIQUE);
CREATE TABLE IF NOT EXISTS virtual_users (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, domain_id INT NOT NULL, email VARCHAR(100) NOT NULL UNIQUE, password VARCHAR(255) NOT NULL, maildir VARCHAR(255) NOT NULL, FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS virtual_aliases (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, domain_id INT NOT NULL, source VARCHAR(100) NOT NULL, destination VARCHAR(100) NOT NULL, FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE);
INSERT IGNORE INTO virtual_domains (name) VALUES ('webiime.ir');
SQL

# Deploy Postfix configs
install -m 644 mail_server/postfix/main.cf /etc/postfix/main.cf
install -m 644 mail_server/postfix/master.cf /etc/postfix/master.cf
install -m 640 mail_server/postfix/mysql-virtual-mailbox-maps.cf /etc/postfix/mysql-virtual-mailbox-maps.cf
install -m 640 mail_server/postfix/mysql-virtual-alias-maps.cf /etc/postfix/mysql-virtual-alias-maps.cf
systemctl restart postfix

# Deploy Dovecot configs
install -m 644 mail_server/dovecot/dovecot.conf /etc/dovecot/dovecot.conf
install -m 640 mail_server/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext
systemctl restart dovecot

# Configure OpenDKIM
mkdir -p /etc/opendkim/keys/webiime.ir
install -m 644 mail_server/opendkim/opendkim.conf /etc/opendkim.conf
if [[ -f mail_server/opendkim/mail.private ]]; then
  install -m 600 mail_server/opendkim/mail.private /etc/opendkim/keys/webiime.ir/mail.private
fi
chown -R opendkim:opendkim /etc/opendkim/keys
systemctl enable --now opendkim

# Certbot DNS-01 via Cloudflare
if [[ -f .env ]]; then
  source .env
  mkdir -p /root/.secrets/certbot
  cat > /root/.secrets/certbot/cloudflare.ini <<EOF
# Cloudflare API token
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF
  chmod 600 /root/.secrets/certbot/cloudflare.ini
  certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini -d mail.webiime.ir -d '*.webiime.ir' --non-interactive --agree-tos -m admin@webiime.ir
  systemctl reload postfix dovecot
  echo "0 3 * * * root certbot renew --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini --deploy-hook 'systemctl reload postfix dovecot nginx'" > /etc/cron.d/certbot-mail
fi

# Django and Gunicorn setup
cd /opt
if [[ ! -d django_webmail ]]; then
  cp -r /workspace/sinamonlate/django_webmail /opt/
fi
python3 -m venv /opt/django_webmail/.venv
source /opt/django_webmail/.venv/bin/activate
pip install --upgrade pip
pip install django gunicorn mysqlclient
cd /opt/django_webmail
python manage.py migrate --noinput
python manage.py createsuperuser --username admin --email admin@webiime.ir --noinput || true

cat > /etc/systemd/system/gunicorn-webmail.service <<'SERVICE'
[Unit]
Description=Gunicorn for webiime webmail
After=network.target

[Service]
User=root
WorkingDirectory=/opt/django_webmail
Environment="DJANGO_SETTINGS_MODULE=webmail_app.settings"
ExecStart=/opt/django_webmail/.venv/bin/gunicorn webmail_app.wsgi:application --bind unix:/run/gunicorn-webmail.sock
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable --now gunicorn-webmail

# Nginx reverse proxy
cat > /etc/nginx/sites-available/mail.webiime.ir <<'NGINX'
server {
    listen 80;
    server_name mail.webiime.ir;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name mail.webiime.ir;

    ssl_certificate /etc/letsencrypt/live/mail.webiime.ir/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mail.webiime.ir/privkey.pem;

    location /static/ {
        alias /opt/django_webmail/static/;
    }

    location / {
        proxy_pass http://unix:/run/gunicorn-webmail.sock;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/mail.webiime.ir /etc/nginx/sites-enabled/mail.webiime.ir
nginx -t && systemctl reload nginx

echo "Installation completed for mail.webiime.ir"
