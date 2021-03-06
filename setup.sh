#!/usr/bin/env bash
set -e

if [ "$EUID" -ne 0 ]; then
	log "Not root"
	exit 1
fi

# ===========================================================================
# This is not functional until I can add dynamic detection of the ADMINFOLDER
# My test one is hardcoded here, but will be replaced in a later version
# Stay tuned
# ===========================================================================

INSTALLER="https://github.com/0x9090/PrestaShopPackage/raw/master/prestashop_1.7.7.5.zip"
ADMINFOLDER="admin3128ztahq"

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
apt install php7.3 php7.3-fpm php7.3-zip php7.3-xml php7.3-curl php7.3-gd php7.3-mysql php7.3-intl php7.3-mbstring mariadb-server mariadb-client -y

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
mkdir -p /var/log/nginx/
mkdir -p /etc/nginx/sites-available/
rm -rf /etc/nginx/conf.d/*
chmod 775 /run/php/php7.3-fpm.sock
chown www-data:www-data /run/php/php7.3-fpm.sock
usermod -a -G www-data nginx
cat > /etc/nginx/sites-available/prestashop.conf<< EOF
server {
	listen 80;
	server_name shop.conceptarms.com;
	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log;
	client_max_body_size 100M;
	charset utf-8;
	root /var/www/;
	index index.php;
	error_page 404 /index.php?controller=404;
	gzip on;
	gzip_disable msie6;
	gzip_vary on;
	gzip_proxied any;
	gzip_static on;
	gzip_buffers 16 8k;
	gzip_http_version 1.1;
	gzip_comp_level 6;
	gzip_min_length 1100;
	gzip_disable "MSIE [1-6]\.(?!.*SV1)";
	gzip_types
    application/atom+xml
    application/javascript
    application/json
    application/ld+json
    application/manifest+json
    application/rss+xml
    application/vnd.geo+json
    application/vnd.ms-fontobject
    application/x-font-ttf
    application/x-web-app-manifest+json
    application/xhtml+xml
    application/xml
    font/opentype
    image/bmp
    image/svg+xml
    image/x-icon
    text/cache-manifest
    text/css
    text/plain
    text/vcard
    text/vnd.rim.location.xloc
    text/vtt
    text/x-component
    text/x-cross-domain-policy;
  location ~* \.(eot|otf|ttf|woff(?:2)?)$ {  # Cloudflare CDN fix
    add_header Access-Control-Allow-Origin *;
  }
  location ~* \.(?:jpg|jpeg|gif|png|ico|css|woff2)$ {
    expires 1M;
    add_header Cache-Control "public";
  }
  location ~* \.pdf$ {
    add_header Content-Disposition Attachment;
    add_header X-Content-Type-Options nosniff;
  }
  location ~ ^/upload/ {
    add_header Content-Disposition Attachment;
    add_header X-Content-Type-Options nosniff;
  }
  location = /favicon.ico {
    auth_basic off;
    allow all;
    log_not_found off;
    access_log off;
  }
  location = /robots.txt {
    auth_basic off;
    allow all;
    log_not_found off;
    access_log off;
  }
  rewrite ^/([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$1$2$3.jpg last;
  rewrite ^/([0-9])([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$2/$1$2$3$4.jpg last;
  rewrite ^/([0-9])([0-9])([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$2/$3/$1$2$3$4$5.jpg last;
  rewrite ^/([0-9])([0-9])([0-9])([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$2/$3/$4/$1$2$3$4$5$6.jpg last;
  rewrite ^/([0-9])([0-9])([0-9])([0-9])([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$2/$3/$4/$5/$1$2$3$4$5$6$7.jpg last;
  rewrite ^/([0-9])([0-9])([0-9])([0-9])([0-9])([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$2/$3/$4/$5/$6/$1$2$3$4$5$6$7$8.jpg last;
  rewrite ^/([0-9])([0-9])([0-9])([0-9])([0-9])([0-9])([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$2/$3/$4/$5/$6/$7/$1$2$3$4$5$6$7$8$9.jpg last;
  rewrite ^/([0-9])([0-9])([0-9])([0-9])([0-9])([0-9])([0-9])([0-9])(-[_a-zA-Z0-9-]*)?(-[0-9]+)?/.+.jpg$ /img/p/$1/$2/$3/$4/$5/$6/$7/$8/$1$2$3$4$5$6$7$8$9$10.jpg last;
  rewrite ^/c/([0-9]+)(-[.*_a-zA-Z0-9-]*)(-[0-9]+)?/.+.jpg$ /img/c/$1$2$3.jpg last;
  rewrite ^/c/([a-zA-Z_-]+)(-[0-9]+)?/.+.jpg$ /img/c/$1$2.jpg last;
  rewrite ^images_ie/?([^/]+)\.(jpe?g|png|gif)$ js/jquery/plugins/fancybox/images/$1.$2 last;
  rewrite ^/api/?(.*)$ /webservice/dispatcher.php?url=$1 last;
  rewrite ^(/install(?:-dev)?/sandbox)/(.*) /$1/test.php last;
  location /$(ADMINFOLDER)/ {  # Change this block to your admin folder
    if (!-e $request_filename) {
      rewrite ^/.*$ /$(ADMINFOLDER)/index.php last;
    }
  }
  location ~ /\. {
    deny all;
  }
  location ~ ^/(app|bin|cache|classes|config|controllers|docs|localization|override|src|tests|tests-legacy|tools|translations|travis-scripts|vendor|var)/ {
    deny all;
  }
  location ~ ^/modules/.*/vendor/ {
    deny all;
  }
  location ~ \.(yml|log|tpl|twig|sass)$ {
    deny all;
  }
  location /upload {
    location ~ \.php$ {
      deny all;
    }
  }
  location /img {
    location ~ \.php$ {
      deny all;
    }
  }
	location ~ \.php$ {
	  try_files $fastcgi_script_name /index.php$uri&$args =404;
	  fastcgi_index  index.php;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
		include fastcgi_params;
		fastcgi_param PATH_INFO       $fastcgi_path_info;
    fastcgi_param PATH_TRANSLATED $document_root$fastcgi_path_info;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_intercept_errors on;
		fastcgi_pass unix:/run/php/php7.3-fpm.sock;
		fastcgi_connect_timeout 75;
		fastcgi_keep_conn on;
		fastcgi_read_timeout 1000;
		fastcgi_send_timeout 1000;
		client_max_body_size 10M;
	}
}
EOF
ln -s /etc/nginx/sites-available/prestashop.conf /etc/nginx/conf.d/prestashop.conf
systemctl restart nginx.service

# ---- Setup PrestaShop ---- #
mkdir -p /var/www/
rm -rf /var/www/*
curl -L ${INSTALLER} --output ~/installer.zip
unzip -o ~/installer.zip -d /var/www/
chown -R www-data:www-data /var/www/
chmod -R 774 /var/www/
systemctl restart nginx.service
echo -e "PrestaShop DB User: prestashop\nPassword:$(cat ~/prestashop_db_pw)"
read -p "Do you want to apply the ps_facebook hotfix?" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  curl -L "https://github.com/0x9090/PrestaShopPackage/raw/master/v1.12.0-ps_facebook.zip" --output ~/ps_facebook.zip
  rm -rf /var/www/modules/ps_facebook/
  unzip -o ~/ps_facebook.zip -d /var/www/modules/
  #rm ~/ps_facebook.zip
  echo "Fixed"
fi
read -p "Ready to delete the 'install' folder? Make sure to navigate to the /admin path to get the admin URL first." -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  rm -rf /var/www/install/
  rm -rf /var/www/docs/
fi
chown -R www-data:www-data /var/www/
chmod -R 774 /var/www/
# ---- TLS ---- #
