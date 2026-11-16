#!/bin/bash
# Descarga y despliega PrestaShop en Apache
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

for var in DB_PASS PS_ADMIN_EMAIL PS_ADMIN_PASS; do
  if [[ "${!var}" == CAMBIAR* ]]; then
    echo "ERROR: define ${var} en scripts/.env.local" >&2
    exit 1
  fi
done

RAIZ_WEB="/var/www/html"
TEMPORAL="$(mktemp -d)"

echo "[1/6] Descargando PrestaShop ${PS_VERSION}"
curl -fL -o "$TEMPORAL/prestashop.zip" \
  "https://assets.prestashop3.com/dst/edition/corporate/${PS_VERSION}/prestashop_edition_classic_version_${PS_VERSION}.zip?source=vagrant"

echo "[2/6] Descomprimiendo en ${RAIZ_WEB}"
unzip -q "$TEMPORAL/prestashop.zip" -d "$TEMPORAL/paquete"
rm -f "$RAIZ_WEB/index.html"
unzip -q -o "$TEMPORAL/paquete/prestashop.zip" -d "$RAIZ_WEB"

echo "[3/6] Ajustando permisos"
chown -R www-data:www-data "$RAIZ_WEB"
rm -rf "$TEMPORAL"

echo "PrestaShop descomprimido en ${RAIZ_WEB}"


echo "[4/6] Instalando PhpPsInfo (comprobación de requisitos)"
curl -fsSL -o "$RAIZ_WEB/phppsinfo.php" \
  https://raw.githubusercontent.com/PrestaShop/php-ps-info/master/phppsinfo.php
sed -i "s/const DEFAULT_LOGIN = '[^']*';/const DEFAULT_LOGIN = 'psinfo';/" "$RAIZ_WEB/phppsinfo.php"
sed -i "s/const DEFAULT_PASSWORD = '[^']*';/const DEFAULT_PASSWORD = '${PS_ADMIN_PASS}';/" "$RAIZ_WEB/phppsinfo.php"
chown www-data:www-data "$RAIZ_WEB/phppsinfo.php"
echo "PhpPsInfo disponible en https://${DOMINIO}/phppsinfo.php"


echo "[5/6] Instalando PrestaShop por línea de comandos"
cd "$RAIZ_WEB/install"
runuser -u www-data -- php index_cli.php \
  --domain="${DOMINIO}" \
  --ssl=1 \
  --db_server=localhost \
  --db_name="${DB_NAME}" \
  --db_user="${DB_USER}" \
  --db_password="${DB_PASS}" \
  --prefix=cb_ \
  --name="${PS_NOMBRE_TIENDA}" \
  --firstname="${PS_NOMBRE_ADMIN}" \
  --lastname="${PS_APELLIDOS_ADMIN}" \
  --email="${PS_ADMIN_EMAIL}" \
  --password="${PS_ADMIN_PASS}" \
  --country="${PS_PAIS}" \
  --language="${PS_IDIOMA}" \
  --timezone="${PS_ZONA_HORARIA}"
cd /
echo "PrestaShop instalado"


echo "[6/6] Limpieza de seguridad"
rm -rf "$RAIZ_WEB/install"
rm -f "$RAIZ_WEB/phppsinfo.php"
echo "Carpeta install y PhpPsInfo eliminados"
