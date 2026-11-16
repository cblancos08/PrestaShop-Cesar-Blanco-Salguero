#!/bin/bash
# Pide un certificado de Let's Encrypt
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

if [[ -z "${DUCKDNS_TOKEN:-}" ]]; then
  echo "ERROR: falta la variable DUCKDNS_TOKEN en el equipo anfitrión" >&2
  exit 1
fi
if [[ "${LE_EMAIL}" == CAMBIAR* ]]; then
  echo "ERROR: define LE_EMAIL en scripts/.env.local" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
CARPETA_HOOKS="/etc/letsencrypt/duckdns"

echo "[1/5] Instalando certbot"
apt-get update -qq
apt-get install -y -qq certbot

echo "[2/5] Guardando el token para las renovaciones"
install -d -m 700 "$CARPETA_HOOKS"
printf 'DUCKDNS_TOKEN=%s\n' "$DUCKDNS_TOKEN" > "$CARPETA_HOOKS/duckdns.env"
chmod 600 "$CARPETA_HOOKS/duckdns.env"

echo "[3/5] Creando los scripts del desafío DNS-01"
cat > "$CARPETA_HOOKS/auth-hook.sh" <<'EOF'
#!/bin/bash
# Crea el registro TXT _acme-challenge en DuckDNS
source /etc/letsencrypt/duckdns/duckdns.env
SUB="${CERTBOT_DOMAIN%.duckdns.org}"
RESPUESTA="$(curl -s "https://www.duckdns.org/update?domains=${SUB}&token=${DUCKDNS_TOKEN}&txt=${CERTBOT_VALIDATION}")"
if [[ "$RESPUESTA" != "OK" ]]; then
  echo "DuckDNS no aceptó el registro TXT" >&2
  exit 1
fi
sleep 30
EOF

cat > "$CARPETA_HOOKS/cleanup-hook.sh" <<'EOF'
#!/bin/bash
# Borra el registro TXT cuando termina la validación
source /etc/letsencrypt/duckdns/duckdns.env
SUB="${CERTBOT_DOMAIN%.duckdns.org}"
curl -s "https://www.duckdns.org/update?domains=${SUB}&token=${DUCKDNS_TOKEN}&txt=borrar&clear=true" > /dev/null
EOF

install -d /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/recargar-apache.sh <<'EOF'
#!/bin/bash
systemctl reload apache2 || true
EOF
chmod 700 "$CARPETA_HOOKS/auth-hook.sh" "$CARPETA_HOOKS/cleanup-hook.sh"
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/recargar-apache.sh

echo "[4/5] Pidiendo el certificado para ${DOMINIO}"
OPCION_STAGING=()
if [[ "${LE_STAGING}" == "true" ]]; then
  OPCION_STAGING=(--staging)
  echo "Modo de PRUEBA (staging): el certificado no será de confianza"
fi

# Si pasamos de staging a real, eliminamos el certificado de prueba
RENOVACION="/etc/letsencrypt/renewal/${DOMINIO}.conf"
if [[ "${LE_STAGING}" != "true" && -f "$RENOVACION" ]] && grep -q "staging" "$RENOVACION"; then
  certbot delete --cert-name "$DOMINIO" --non-interactive
fi

certbot certonly --manual --preferred-challenges dns \
  --manual-auth-hook "$CARPETA_HOOKS/auth-hook.sh" \
  --manual-cleanup-hook "$CARPETA_HOOKS/cleanup-hook.sh" \
  -d "$DOMINIO" --cert-name "$DOMINIO" \
  --email "$LE_EMAIL" --agree-tos --no-eff-email \
  --non-interactive --keep-until-expiring \
  "${OPCION_STAGING[@]}"

echo "Certificado obtenido correctamente"


echo "[5/5] Activando HTTPS en Apache"
a2enmod ssl headers rewrite > /dev/null
sed "s/__DOMINIO__/${DOMINIO}/g" "$RAIZ_REPO/conf/000-default.conf" \
  > /etc/apache2/sites-available/000-default.conf
sed "s/__DOMINIO__/${DOMINIO}/g" "$RAIZ_REPO/conf/default-ssl.conf" \
  > /etc/apache2/sites-available/default-ssl.conf
a2ensite default-ssl > /dev/null
apache2ctl configtest
systemctl restart apache2
echo "HTTPS activado en https://${DOMINIO}"
