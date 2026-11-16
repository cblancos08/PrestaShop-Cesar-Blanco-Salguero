#!/bin/bash
# Instala la pila LAMP (Apache, MariaDB, PHP) y phpMyAdmin en Debian 12
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ_REPO="$(dirname "$DIR")"

cargar_env() {
  set -a
  source <(sed 's/\r$//' "$1")
  set +a
}

cargar_env "$DIR/.env"
if [[ -f "$DIR/.env.local" ]]; then
  cargar_env "$DIR/.env.local"
fi

for var in DB_PASS PMA_APP_PASS; do
  if [[ "${!var}" == CAMBIAR* ]]; then
    echo "ERROR: define ${var} en scripts/.env.local" >&2
    exit 1
  fi
done

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Actualizando paquetes"
apt-get update -qq

echo "[2/7] Instalando Apache, MariaDB y PHP"
apt-get install -y -qq apache2 mariadb-server php libapache2-mod-php php-cli \
  php-mysql php-curl php-gd php-intl php-mbstring php-xml php-zip php-bcmath \
  unzip curl openssl ca-certificates

echo "[3/7] Configurando PHP para PrestaShop"
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
for sapi in apache2 cli; do
  cat > "/etc/php/${PHP_VER}/${sapi}/conf.d/99-prestashop.ini" <<EOF
memory_limit = ${PHP_MEMORY_LIMIT}
max_input_vars = ${PHP_MAX_INPUT_VARS}
post_max_size = ${PHP_POST_MAX_SIZE}
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}
date.timezone = ${PS_ZONA_HORARIA}
EOF
done

echo "[4/7] Creando la base de datos y el usuario"
mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "[5/7] Instalando phpMyAdmin"
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password ${PMA_APP_PASS}" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password ${PMA_APP_PASS}" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt-get install -y -qq phpmyadmin

echo "[6/7] Configurando Apache"
a2enmod rewrite ssl headers >/dev/null
echo "ServerName ${DOMINIO}" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null
sed "s/__DOMINIO__/${DOMINIO}/g" "$RAIZ_REPO/conf/000-default.conf" \
  > /etc/apache2/sites-available/000-default.conf
apache2ctl configtest
systemctl restart apache2

echo "[7/7] Comprobación final"
systemctl is-active apache2 mariadb
php -v | head -n 1
echo "LAMP instalada correctamente"