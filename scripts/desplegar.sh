#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Despliega el foro en la maquina actual (pensado para Play with Docker).
#
#  Uso:
#    ./scripts/desplegar.sh            # usa el .env existente
#
#  Comprueba que esten .env y, si PERFIL=oracle, el Wallet en wallet/.
#  Acepta el Wallet como Wallet_*.zip en la carpeta actual y lo descomprime.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "Falta .env: cp .env.example .env y completalo" >&2; exit 1; }
set -a; source .env; set +a

if [ "${PERFIL:-oracle}" = "oracle" ]; then
  if [ ! -f wallet/tnsnames.ora ]; then
    ZIP="$(ls Wallet_*.zip 2>/dev/null | head -1 || true)"
    [ -n "$ZIP" ] || { echo "Falta el Wallet: sube Wallet_XXX.zip a esta carpeta" >&2; exit 1; }
    mkdir -p wallet && unzip -o -q "$ZIP" -d wallet
    echo "Wallet descomprimido desde $ZIP"
  fi
  # Los contenedores corren con un usuario sin privilegios: tiene que poder leerlo.
  chmod -R a+rX wallet
  [ -n "${ORACLE_PASSWORD:-}" ] || { echo "Falta ORACLE_PASSWORD en .env" >&2; exit 1; }
else
  mkdir -p wallet
fi

docker compose pull
docker compose up -d
echo
docker compose ps
echo
echo "Comprobacion (espera ~40 s a que arranquen los servicios Java):"
for p in 8081 8082 8083; do
  echo "  curl -s localhost:$p/api/estado"
done
