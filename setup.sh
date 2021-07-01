#!/usr/bin/env bash
set -e

if [ "$EUID" -ne 0 ]; then
	log "Not root"
	exit 1
fi

INSTALLER=""

# ---- Set up Iptables ---- #
#iptables -P INPUT ACCEPT
iptables -F
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# --- Download & Install dependencies ---- #
apt update
apt upgrade -y
apt install unattended-upgrades apt-transport-https curl gnupg2 unzip ca-certificates lsb-release software-properties-common dirmngr -y
echo "deb http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx
echo "deb https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/php.list
echo "deb [arch=amd64,arm64,ppc64el] http://nyc2.mirrors.digitalocean.com/mariadb/repo/10.5/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/mariadb.list
curl -o /etc/apt/trusted.gpg.d/nginx.asc https://nginx.org/keys/nginx_signing.key
curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
curl -o /etc/apt/trusted.gpg.d/mariadb.asc https://mariadb.org/mariadb_release_signing_key.asc
apt update
apt install nginx -y
apt install php7.4 php7.4-fpm mariadb-server mariadb-client -y
rm -rf prestashop/
unzip -o prestashop_*.zip -d prestashop

# ---- Set up Database ---- #
if [ ! -f ~/mariadb_root_pw ]; then
	pass=$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c14; echo)
	echo ${pass} >> ~/mariadb_root_pw
	mysql --user=root --password="${pass}" -e "SET PASSWORD FOR root@localhost = PASSWORD('${pass}');"
else
	pass=$(cat ~/mariadb_root_pw)
fi
if ! mysql --user=root --password="${pass}" -e "USE prestashop"; then
	mysql --user=root --password="${pass}" -e "CREATE DATABASE prestashop;"
fi
if [ ! -f ~/prestashop_db_pw ]; then
	pass2=$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c14; echo)
	echo ${pass2} >> ~/prestashop_db_pw
	mysql --force --user=root --password="${pass}" -e "CREATE USER 'prestashop'@'localhost' IDENTIFIED BY '${pass2}'"
	mysql --force --user=root --password="${pass}" -e "GRANT ALL ON prestashop.* TO 'prestashop'@'localhost' IDENTIFIED BY '${pass2}' WITH GRANT OPTION;"
	mysql --force --user=root --password="${pass}" -e "FLUSH PRIVILEGES;"
fi

# ---- Set up Nginx ---- #
mkdir -p /etc/nginx/sites-available/
mkdir -p /etc/nginx/sites-enabled/
rm -rf /etc/nginx/sites-enabled/*
cat > /etc/nginx/sites-available/prestashop.conf<< EOF
server {
	listen 0.0.0.0:80 default_server;
	server_name shop.conceptarms.com;
	access_log /var/log/nignx/access.log;
	error_log /var/log/nginx/error.log;
	client_max_body_size 100M;
	charset utf-8;
	root /var/www;
	index index.html index.php;
	location / {
		try_files $uri $uri/ =404;
	}
	location ~ \.php$ {
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
	}
}
EOF
ln -s /etc/nginx/sites-available/prestashop.conf /etc/nginx/sites-enabled/prestashop.conf
systemctl restart nginx.service

# copy the unzipped presta shop to /var/www
# restart nginxi

# ---- TLS ---- #
